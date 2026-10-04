package store

import (
	"context"
	"os"
	"testing"
	"time"
)

func TestPostgresIntegration(t *testing.T) {
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("set TEST_DATABASE_URL to a disposable PostgreSQL database")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	s, err := Open(ctx, url)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	for i := 0; i < 2; i++ {
		if err := s.Migrate(ctx); err != nil {
			t.Fatalf("migration attempt %d: %v", i+1, err)
		}
	}
	if err := s.Ready(ctx); err != nil {
		t.Fatal(err)
	}
	created, err := s.Create(ctx, "integration message")
	if err != nil {
		t.Fatal(err)
	}
	if created.ID < 1 || created.Text != "integration message" || created.CreatedAt.IsZero() {
		t.Fatalf("unexpected created message: %+v", created)
	}
	items, err := s.List(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != 1 || items[0].ID != created.ID {
		t.Fatalf("unexpected messages: %+v", items)
	}
	if _, err := s.Create(ctx, ""); err == nil {
		t.Fatal("expected PostgreSQL CHECK constraint to reject empty text")
	}
}
