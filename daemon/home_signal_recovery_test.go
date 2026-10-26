package client

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

func homeSignalTestUnavailable() error {
	return status.Error(codes.Unavailable, "signal unavailable")
}

func homeSignalTestDeadline() error {
	return status.Error(codes.DeadlineExceeded, "signal deadline exceeded")
}

func homeSignalTestRecovery() (*homeSignalRecovery, time.Time) {
	return &homeSignalRecovery{}, time.Date(2026, time.January, 1, 12, 0, 0, 0, time.UTC)
}

func TestHomeSignalRecoveryRequiresThreeRecoverableErrorsOver45Seconds(t *testing.T) {
	r, base := homeSignalTestRecovery()
	var probes, recovers int
	probe := func(context.Context) error {
		probes++
		return nil
	}
	recoverProcess := func() { recovers++ }

	// Two recoverable failures spanning 30 seconds are not enough.
	r.observe(context.Background(), homeSignalTestUnavailable(), base, probe, recoverProcess)
	r.observe(context.Background(), homeSignalTestDeadline(), base.Add(30*time.Second), probe, recoverProcess)
	if probes != 0 || recovers != 0 {
		t.Fatalf("recovery triggered before three failures: probes=%d recovers=%d", probes, recovers)
	}

	// Three failures must also span at least 45 seconds.
	short, shortBase := homeSignalTestRecovery()
	var shortProbes, shortRecovers int
	shortProbe := func(context.Context) error {
		shortProbes++
		return nil
	}
	shortRecover := func() { shortRecovers++ }
	short.observe(context.Background(), homeSignalTestUnavailable(), shortBase, shortProbe, shortRecover)
	short.observe(context.Background(), homeSignalTestUnavailable(), shortBase.Add(time.Second), shortProbe, shortRecover)
	short.observe(context.Background(), homeSignalTestUnavailable(), shortBase.Add(44*time.Second), shortProbe, shortRecover)
	if shortProbes != 0 || shortRecovers != 0 {
		t.Fatalf("recovery triggered before 45 seconds: probes=%d recovers=%d", shortProbes, shortRecovers)
	}

	// The third failure at exactly 45 seconds starts one probe and recovery.
	r.observe(context.Background(), homeSignalTestUnavailable(), base.Add(45*time.Second), probe, recoverProcess)
	if probes != 1 || recovers != 1 {
		t.Fatalf("expected one probe and one recovery, got probes=%d recovers=%d", probes, recovers)
	}
}

func TestHomeSignalRecoveryFreshProbeFailureNeverRestarts(t *testing.T) {
	r, base := homeSignalTestRecovery()
	var probes, recovers int
	probe := func(context.Context) error {
		probes++
		return homeSignalTestUnavailable()
	}
	recoverProcess := func() { recovers++ }

	r.observe(context.Background(), homeSignalTestUnavailable(), base, probe, recoverProcess)
	r.observe(context.Background(), homeSignalTestUnavailable(), base.Add(time.Second), probe, recoverProcess)
	r.observe(context.Background(), homeSignalTestUnavailable(), base.Add(45*time.Second), probe, recoverProcess)
	if probes != 1 {
		t.Fatalf("expected one fresh probe, got %d", probes)
	}
	if recovers != 0 {
		t.Fatalf("fresh probe failure must not restart, got %d restarts", recovers)
	}

	// A failed probe also starts the probe cooldown.
	r.observe(context.Background(), homeSignalTestUnavailable(), base.Add(50*time.Second), probe, recoverProcess)
	if probes != 1 || recovers != 0 {
		t.Fatalf("probe cooldown ignored after failure: probes=%d recovers=%d", probes, recovers)
	}
}

func TestHomeSignalRecoverySuccessResetsFailures(t *testing.T) {
	r, base := homeSignalTestRecovery()
	var probes, recovers int
	probe := func(context.Context) error {
		probes++
		return nil
	}
	recoverProcess := func() { recovers++ }

	r.observe(context.Background(), homeSignalTestUnavailable(), base, probe, recoverProcess)
	r.observe(context.Background(), homeSignalTestUnavailable(), base.Add(time.Second), probe, recoverProcess)
	r.observe(context.Background(), nil, base.Add(2*time.Second), probe, recoverProcess)

	r.mu.Lock()
	failures := r.failures
	since := r.since
	r.mu.Unlock()
	if failures != 0 || !since.IsZero() {
		t.Fatalf("success did not reset state: failures=%d since=%v", failures, since)
	}

	// A new run of failures must accumulate its own 45-second window.
	r.observe(context.Background(), homeSignalTestUnavailable(), base.Add(3*time.Second), probe, recoverProcess)
	r.observe(context.Background(), homeSignalTestUnavailable(), base.Add(4*time.Second), probe, recoverProcess)
	r.observe(context.Background(), homeSignalTestUnavailable(), base.Add(5*time.Second), probe, recoverProcess)
	if probes != 0 || recovers != 0 {
		t.Fatalf("old failure window survived success: probes=%d recovers=%d", probes, recovers)
	}

	r.observe(context.Background(), homeSignalTestUnavailable(), base.Add(48*time.Second), probe, recoverProcess)
	if probes != 1 || recovers != 1 {
		t.Fatalf("new 45-second window did not recover: probes=%d recovers=%d", probes, recovers)
	}
}

func TestHomeSignalRecoveryCancelledContextNeverProbesOrRestarts(t *testing.T) {
	t.Run("cancelled before observe", func(t *testing.T) {
		r, base := homeSignalTestRecovery()
		var probes, recovers int
		probe := func(context.Context) error {
			probes++
			return nil
		}
		recoverProcess := func() { recovers++ }

		// Seed a state that would otherwise recover immediately.
		r.failures = 3
		r.since = base.Add(-time.Hour)

		ctx, cancel := context.WithCancel(context.Background())
		cancel()

		r.observe(ctx, homeSignalTestUnavailable(), base, probe, recoverProcess)
		r.observe(ctx, homeSignalTestUnavailable(), base.Add(time.Hour), probe, recoverProcess)
		if probes != 0 || recovers != 0 {
			t.Fatalf("cancelled context probed or restarted: probes=%d recovers=%d", probes, recovers)
		}

		r.mu.Lock()
		failures := r.failures
		since := r.since
		r.mu.Unlock()
		if failures != 0 || !since.IsZero() {
			t.Fatalf("cancelled context did not reset state: failures=%d since=%v", failures, since)
		}
	})

	t.Run("cancelled during probe", func(t *testing.T) {
		r, base := homeSignalTestRecovery()
		var probes, recovers int
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()

		probe := func(context.Context) error {
			probes++
			cancel()
			return nil
		}
		recoverProcess := func() { recovers++ }

		r.observe(ctx, homeSignalTestUnavailable(), base, probe, recoverProcess)
		r.observe(ctx, homeSignalTestUnavailable(), base.Add(time.Second), probe, recoverProcess)
		r.observe(ctx, homeSignalTestUnavailable(), base.Add(45*time.Second), probe, recoverProcess)

		if probes != 1 {
			t.Fatalf("expected the fresh probe to run, got %d", probes)
		}
		if recovers != 0 {
			t.Fatalf("context cancelled during probe must not restart, got %d restarts", recovers)
		}
	})
}

func TestHomeSignalRecoveryProbeCooldown(t *testing.T) {
	r, base := homeSignalTestRecovery()
	var probes, recovers int
	probe := func(context.Context) error {
		probes++
		return nil
	}
	recoverProcess := func() { recovers++ }

	r.observe(context.Background(), homeSignalTestUnavailable(), base, probe, recoverProcess)
	r.observe(context.Background(), homeSignalTestUnavailable(), base.Add(time.Second), probe, recoverProcess)
	r.observe(context.Background(), homeSignalTestUnavailable(), base.Add(45*time.Second), probe, recoverProcess)
	if probes != 1 || recovers != 1 {
		t.Fatalf("expected the first recovery, got probes=%d recovers=%d", probes, recovers)
	}

	// One second before the two-minute cooldown expires, no new probe runs.
	r.observe(context.Background(), homeSignalTestUnavailable(), base.Add(2*time.Minute+44*time.Second), probe, recoverProcess)
	if probes != 1 || recovers != 1 {
		t.Fatalf("probe ran before cooldown expired: probes=%d recovers=%d", probes, recovers)
	}

	// Exactly two minutes later the cooldown is over.
	r.observe(context.Background(), homeSignalTestUnavailable(), base.Add(2*time.Minute+45*time.Second), probe, recoverProcess)
	if probes != 2 || recovers != 2 {
		t.Fatalf("probe did not run after cooldown: probes=%d recovers=%d", probes, recovers)
	}
}

func TestHomeSignalRecoveryInterveningSuccessCancelsRecovery(t *testing.T) {
	r, base := homeSignalTestRecovery()
	var probes, recovers int
	recoverProcess := func() { recovers++ }
	probe := func(ctx context.Context) error {
		probes++
		// A successful RPC lands while the independent probe is in flight.
		r.observe(ctx, nil, base.Add(45*time.Second), nil, nil)
		return nil
	}

	r.observe(context.Background(), homeSignalTestUnavailable(), base, probe, recoverProcess)
	r.observe(context.Background(), homeSignalTestUnavailable(), base.Add(time.Second), probe, recoverProcess)
	r.observe(context.Background(), homeSignalTestUnavailable(), base.Add(45*time.Second), probe, recoverProcess)
	if probes != 1 {
		t.Fatalf("expected one probe, got %d", probes)
	}
	if recovers != 0 {
		t.Fatalf("intervening success must cancel recovery, got %d restarts", recovers)
	}

	r.mu.Lock()
	failures := r.failures
	since := r.since
	r.mu.Unlock()
	if failures != 0 || !since.IsZero() {
		t.Fatalf("intervening success did not reset state: failures=%d since=%v", failures, since)
	}

	// A later single failure starts a new window rather than recovering at once.
	r.observe(context.Background(), homeSignalTestUnavailable(), base.Add(46*time.Second), probe, recoverProcess)
	if probes != 1 || recovers != 0 {
		t.Fatalf("recovery resumed without a new failure window: probes=%d recovers=%d", probes, recovers)
	}
}

func TestHomeSignalRestartBudgetSequence(t *testing.T) {
	stateDir := t.TempDir()
	base := time.Date(2026, time.January, 1, 12, 0, 0, 0, time.UTC)

	if !reserveHomeSignalRestart(stateDir, base) {
		t.Fatal("first restart reservation was rejected")
	}
	if reserveHomeSignalRestart(stateDir, base.Add(9*time.Minute)) {
		t.Fatal("restart reservation at nine minutes was allowed")
	}
	if !reserveHomeSignalRestart(stateDir, base.Add(10*time.Minute)) {
		t.Fatal("restart reservation at ten minutes was rejected")
	}
	if !reserveHomeSignalRestart(stateDir, base.Add(20*time.Minute)) {
		t.Fatal("restart reservation at twenty minutes was rejected")
	}
	if reserveHomeSignalRestart(stateDir, base.Add(30*time.Minute)) {
		t.Fatal("restart reservation at thirty minutes was allowed despite three restarts within an hour")
	}
	if !reserveHomeSignalRestart(stateDir, base.Add(61*time.Minute)) {
		t.Fatal("restart reservation at sixty-one minutes was rejected after the hour window")
	}
}

func TestHomeSignalRestartBudgetRejectsInvalidState(t *testing.T) {
	now := time.Date(2026, time.January, 1, 12, 0, 0, 0, time.UTC)

	if reserveHomeSignalRestart("", now) {
		t.Fatal("missing state directory was allowed")
	}

	stateDir := t.TempDir()
	path := filepath.Join(stateDir, "home-signal-recovery.json")
	if err := os.WriteFile(path, []byte("{not-json"), 0600); err != nil {
		t.Fatalf("write corrupt state: %v", err)
	}
	if reserveHomeSignalRestart(stateDir, now) {
		t.Fatal("corrupt restart state was allowed")
	}
}
