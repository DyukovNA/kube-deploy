package api

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"kubedeploy/backend/internal/store"
)

type fakeStore struct {
	readyErr  error
	listErr   error
	createErr error
	items     []store.Message
	created   string
}

func (f *fakeStore) Ready(context.Context) error { return f.readyErr }
func (f *fakeStore) List(context.Context) ([]store.Message, error) {
	return f.items, f.listErr
}
func (f *fakeStore) Create(_ context.Context, text string) (store.Message, error) {
	f.created = text
	return store.Message{ID: 3, Text: text, CreatedAt: time.Date(2026, 10, 4, 0, 0, 0, 0, time.UTC)}, f.createErr
}

func newHandler(f *fakeStore) http.Handler {
	return New(f, slog.New(slog.NewTextHandler(io.Discard, nil)), "sha-test", "test").Handler()
}

func request(t *testing.T, h http.Handler, method, path, body string) *httptest.ResponseRecorder {
	t.Helper()
	r := httptest.NewRequest(method, path, strings.NewReader(body))
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	return w
}

func TestHealthAndVersion(t *testing.T) {
	f := &fakeStore{readyErr: errors.New("database down")}
	h := newHandler(f)
	if got := request(t, h, http.MethodGet, "/api/health/live", "").Code; got != http.StatusOK {
		t.Fatalf("liveness status = %d", got)
	}
	if got := request(t, h, http.MethodGet, "/api/health/ready", "").Code; got != http.StatusServiceUnavailable {
		t.Fatalf("readiness status = %d", got)
	}
	f.readyErr = nil
	if got := request(t, h, http.MethodGet, "/api/health/ready", "").Code; got != http.StatusOK {
		t.Fatalf("readiness status = %d", got)
	}
	w := request(t, h, http.MethodGet, "/api/version", "")
	var result map[string]string
	if err := json.Unmarshal(w.Body.Bytes(), &result); err != nil {
		t.Fatal(err)
	}
	if result["version"] != "sha-test" || result["commit"] != "test" {
		t.Fatalf("unexpected version response: %v", result)
	}
}

func TestCreateMessageValidation(t *testing.T) {
	f := &fakeStore{}
	h := newHandler(f)
	invalid := []string{
		`{}`,
		`{"text":"   "}`,
		`{"text":"ok","unknown":1}`,
		`{"text":"one"}{"text":"two"}`,
		`{"text":"` + strings.Repeat("a", 281) + `"}`,
		`{"text":"` + strings.Repeat("a", 4097) + `"}`,
	}
	for _, body := range invalid {
		if got := request(t, h, http.MethodPost, "/api/messages", body).Code; got != http.StatusBadRequest {
			t.Fatalf("body %q: status = %d", body[:min(len(body), 40)], got)
		}
	}
	w := request(t, h, http.MethodPost, "/api/messages", `{"text":"  Привет 🌿  "}`)
	if w.Code != http.StatusCreated || f.created != "Привет 🌿" {
		t.Fatalf("status = %d, text = %q", w.Code, f.created)
	}
}

func TestListAndDatabaseFailure(t *testing.T) {
	f := &fakeStore{items: []store.Message{{ID: 1, Text: "hello"}}}
	h := newHandler(f)
	w := request(t, h, http.MethodGet, "/api/messages", "")
	if w.Code != http.StatusOK || !strings.Contains(w.Body.String(), `"text":"hello"`) {
		t.Fatalf("status = %d, body = %s", w.Code, w.Body.String())
	}
	f.listErr = errors.New("database down")
	if got := request(t, h, http.MethodGet, "/api/messages", "").Code; got != http.StatusServiceUnavailable {
		t.Fatalf("status = %d", got)
	}
	f.createErr = errors.New("database down")
	if got := request(t, h, http.MethodPost, "/api/messages", `{"text":"hello"}`).Code; got != http.StatusServiceUnavailable {
		t.Fatalf("status = %d", got)
	}
}
