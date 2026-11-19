# SRE - Confiabilidade do donation-service

O `donation-service` é o caminho crítico: se ele falha, a doação não acontece. Os objetivos abaixo valem para ele. Os outros serviços seguem os mesmos sinais (Golden Metrics), sem SLO formal.

## 1. Golden Metrics instrumentadas

Os 3 serviços expõem `/metrics` com os mesmos nomes, o que permite reaproveitar queries e dashboards:

| Golden Metric | Métrica | Labels |
|---|---|---|
| Latência | `http_request_duration_seconds` (histograma, bucket em 0,3 s) | service, method, route |
| Tráfego | `http_requests_total` | service, method, route, code |
| Erros | `http_requests_total{code=~"5.."}` | idem |
| Saturação | `http_requests_in_flight`, CPU/memória vs requests/limits (cAdvisor, kube-state-metrics) | service, container |

Métricas de negócio do donation-service: `donations_created_total`, `donations_amount_brl_total`, `sqs_publish_total{result}`.

Probes (`/health`, `/ready`) e o próprio `/metrics` ficam fora das métricas e dos traces. Assim o SLI mede só tráfego real de usuário.

## 2. Definição formal de SLI, SLO e SLA

### SLI 1 - Disponibilidade

- **Definição:** proporção de requisições ao endpoint `/donations` (POST e GET) que **não** retornaram HTTP 5xx.
- **Fonte:** `http_requests_total{service="donation-service",route="/donations"}`, medido no próprio serviço.
- **Fórmula:**
  `SLI = 1 - sum(rate(http_requests_total{...,code=~"5.."}[janela])) / sum(rate(http_requests_total{...}[janela]))`
- **Fica fora do SLI:** respostas 4xx (erro do cliente, ex.: payload inválido), probes e `/admin/chaos`.

### SLI 2 - Latência

- **Definição:** proporção de requisições a `/donations` respondidas em **menos de 300 ms**.
- **Fórmula:**
  `SLI = sum(rate(http_request_duration_seconds_bucket{...,le="0.3"}[janela])) / sum(rate(http_request_duration_seconds_count{...}[janela]))`

### SLOs (janela móvel de 30 dias)

| SLI | SLO | Error budget | Em tempo (100% do tráfego) |
|---|---|---|---|
| Disponibilidade | **99,9%** | 0,1% das requisições | ~43 min/mês |
| Latência < 300 ms | **95%** | 5% das requisições | - |

### SLA (acordo externo com as ONGs parceiras)

| Item | Compromisso |
|---|---|
| Disponibilidade mensal da API de doações | **99,5%** (mais folgado que o SLO interno de 99,9%) |
| Comunicação de incidente SEV1 | status publicado em até **30 min** |
| Post-mortem de incidente SEV1/SEV2 | publicado em até **5 dias úteis** |
| Integridade das doações | nenhuma doação confirmada (HTTP 201) é perdida: RPO de 5 min na região e 15 min entre regiões (ver `pcn.md`) |
| Contrapartida em caso de violação | por ser uma ONG, não há crédito financeiro. Há relatório de causa raiz e plano de ação com prazo. |

O SLO interno é mais rígido que o SLA de propósito. A equipe é alertada e age bem antes de violar o compromisso externo.

## 3. Implementação

| Item | Arquivo |
|---|---|
| Recording rules (SLI em 5m, 30m, 1h, 2h, 6h, 1d, 3d, 30d; error budget; burn rate) | `solidarytech-deploy/k8s/observability/rules/slo-donation.yaml` |
| Alertas multi-burn-rate | mesmo arquivo, grupo `slo-donation-alerts` |
| Dashboard SRE exclusivo de SLO/Error Budget (Grafana) | `solidarytech-deploy/k8s/observability/dashboards/slo-donation.yaml` |
| SLOs nativos e dashboard SRE no Datadog | `solidarytech-deploy/terraform/datadog/main.tf` |

### Alertas multi-window, multi-burn-rate (Google SRE Workbook)

| Severidade | Burn rate | Janela longa | Janela curta | Significado |
|---|---|---|---|---|
| page (critical) | 14,4x | 1h | 5m | 2% do budget mensal em 1h |
| page (critical) | 6x | 6h | 30m | 5% do budget em 6h |
| ticket (warning) | 3x | 1d | 2h | 10% do budget em 1 dia |
| ticket (warning) | 1x | 3d | 6h | 10% do budget em 3 dias |

A janela curta faz o alerta parar logo que o problema acaba, o que reduz ruído.

### Política de Error Budget

| Budget restante | Ação |
|---|---|
| > 50% | Deploys normais, experimentos permitidos |
| 25% a 50% | Deploys do donation-service exigem revisão de risco e rollback testado |
| < 25% | Congelamento de features no donation-service. Só correções de confiabilidade. |
| Esgotado | Congelamento total e post-mortem obrigatório. Prioridade máxima para os action items. |

## 4. Como a stack reduz o MTTR

MTTR = tempo de detecção + tempo de diagnóstico + tempo de correção.

| Fase | Sem a stack | Com a stack | Mecanismo |
|---|---|---|---|
| Detecção | doador reclama nas redes sociais | **~2 a 5 min** | burn rate 14,4x com `for: 2m`; monitor Datadog `last_5m`; Watchdog detecta anomalia antes de violar o SLO |
| Triagem | quem está de plantão? | imediata | JSM abre o incidente com severidade e notifica o Slack `#alerts` |
| Diagnóstico | SSH e grep em logs | **~5 min** | trace distribuído (Datadog APM) mostra qual span falhou (RDS, SQS); logs JSON correlacionados por `trace_id` (Loki e Datadog Logs); dashboard Golden Signals |
| Correção | manual | **~1 a 2 min** | self-healing: webhook do Datadog dispara o `rollout restart` e a verificação de saúde (`self-healing.yml`); rollback = `git revert` da tag (ArgoCD) |
| Prevenção de recorrência | - | - | post-mortem com action items (`postmortem-template.md`) |

Medição: o MTTR de cada incidente vem da linha do tempo do JSM (abertura até resolução) e do resumo do job de self-healing. Evidência da demo: chaos (`scripts/chaos.sh`), alerta, rollout, recuperação, com os horários de cada etapa no resumo do workflow.

## 5. Demonstração (roteiro)

1. `BASE_URL=http://<elb> ./scripts/load-test.sh` para gerar tráfego. Dashboard SLO com budget em ~100%.
2. `./scripts/chaos.sh on 0.3 0` para injetar 30% de erros 5xx.
3. Dashboard: a taxa de erro de 5m passa do limiar, o burn rate 1h sobe e o error budget começa a cair.
4. Alertas: `DonationSLOAvailabilityBurnRate1h` (Prometheus) e o monitor 5xx do Datadog disparam. O Watchdog aponta a anomalia.
5. Self-healing: `rollout restart` (o chaos fica só em memória, então o restart corrige a falha). O serviço volta.
6. Mostrar o budget consumido no incidente e o MTTR no resumo do workflow.
