package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
)

func newTestApp(t *testing.T) (*App, sqlmock.Sqlmock) {
	t.Helper()
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock: %v", err)
	}
	t.Cleanup(func() { _ = db.Close() })
	return NewApp(db, nil, "", "secret"), mock
}

func TestHealth(t *testing.T) {
	app, _ := newTestApp(t)
	rr := httptest.NewRecorder()
	app.Routes(nil).ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/health", nil))
	if rr.Code != http.StatusOK {
		t.Fatalf("esperado 200, obtido %d", rr.Code)
	}
}

func TestCreateDonationInvalidPayload(t *testing.T) {
	app, _ := newTestApp(t)
	rr := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/donations", strings.NewReader(`{"ngo_id":0}`))
	app.Routes(nil).ServeHTTP(rr, req)
	if rr.Code != http.StatusBadRequest {
		t.Fatalf("esperado 400, obtido %d", rr.Code)
	}
}

func TestCreateDonationOK(t *testing.T) {
	app, mock := newTestApp(t)
	mock.ExpectQuery("INSERT INTO donations").
		WithArgs(1, 50.0, "Maria", "APPROVED").
		WillReturnRows(sqlmock.NewRows([]string{"id", "created_at"}).AddRow(10, time.Now()))

	rr := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/donations",
		strings.NewReader(`{"ngo_id":1,"amount":50,"donor_name":"Maria"}`))
	app.Routes(nil).ServeHTTP(rr, req)

	if rr.Code != http.StatusCreated {
		t.Fatalf("esperado 201, obtido %d: %s", rr.Code, rr.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestMethodNotAllowed(t *testing.T) {
	app, _ := newTestApp(t)
	rr := httptest.NewRecorder()
	app.Routes(nil).ServeHTTP(rr, httptest.NewRequest(http.MethodDelete, "/donations", nil))
	if rr.Code != http.StatusMethodNotAllowed {
		t.Fatalf("esperado 405, obtido %d", rr.Code)
	}
}

func TestChaosRequiresToken(t *testing.T) {
	app, _ := newTestApp(t)
	rr := httptest.NewRecorder()
	app.Routes(nil).ServeHTTP(rr, httptest.NewRequest(http.MethodPost, "/admin/chaos", strings.NewReader(`{"error_rate":1}`)))
	if rr.Code != http.StatusForbidden {
		t.Fatalf("esperado 403, obtido %d", rr.Code)
	}
}

func TestChaosInjectsErrors(t *testing.T) {
	app, _ := newTestApp(t)
	h := app.Routes(nil)

	req := httptest.NewRequest(http.MethodPost, "/admin/chaos", strings.NewReader(`{"error_rate":1}`))
	req.Header.Set("X-Chaos-Token", "secret")
	rr := httptest.NewRecorder()
	h.ServeHTTP(rr, req)
	if rr.Code != http.StatusOK {
		t.Fatalf("esperado 200, obtido %d", rr.Code)
	}

	rr = httptest.NewRecorder()
	h.ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/donations", nil))
	if rr.Code != http.StatusInternalServerError {
		t.Fatalf("esperado 500 com chaos, obtido %d", rr.Code)
	}
}
