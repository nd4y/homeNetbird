package client

import (
    "context"
    "crypto/tls"
    "encoding/json"
    "os"
    "path/filepath"
    "runtime"
    "sync"
    "time"

    log "github.com/sirupsen/logrus"
    "google.golang.org/grpc"
    "google.golang.org/grpc/codes"
    "google.golang.org/grpc/credentials"
    "google.golang.org/grpc/credentials/insecure"
    "google.golang.org/grpc/status"
    "github.com/netbirdio/netbird/shared/signal/proto"
)

// homeSignalRecovery is opt-in for the isolated Windows Home service only.
// A working peer session must survive a genuine remote Signal outage.
type homeSignalRecovery struct {
    mu sync.Mutex
    failures int
    since time.Time
    lastProbe time.Time
    probing bool
}

func (r *homeSignalRecovery) observe(ctx context.Context, err error, now time.Time, probe func(context.Context) error, recoverProcess func()) {
    r.mu.Lock()
    if err == nil { r.failures=0; r.since=time.Time{}; r.mu.Unlock(); return }
    if ctx.Err()!=nil || (status.Code(err)!=codes.DeadlineExceeded && status.Code(err)!=codes.Unavailable) { r.failures=0; r.since=time.Time{}; r.mu.Unlock(); return }
    if r.failures==0 { r.since=now }
    if r.failures<3 { r.failures++ }
    if r.failures<3 || now.Sub(r.since)<45*time.Second || r.probing || (!r.lastProbe.IsZero() && now.Sub(r.lastProbe)<2*time.Minute) { r.mu.Unlock(); return }
    r.probing=true; r.lastProbe=now
    r.mu.Unlock()
    defer func(){r.mu.Lock();r.probing=false;r.mu.Unlock()}()
    checkCtx,cancel:=context.WithTimeout(ctx,8*time.Second)
    defer cancel()
    if probe(checkCtx)!=nil || ctx.Err()!=nil { return }
    // Recheck after the probe: an intervening successful RPC cancels recovery.
    r.mu.Lock(); stillBroken:=r.failures>=3 && !r.since.IsZero(); r.mu.Unlock()
    if stillBroken { recoverProcess() }
}

// Persist the budget across SCM restarts; never create an infinite restart loop.
func reserveHomeSignalRestart(stateDir string, now time.Time) bool {
    if stateDir=="" { return false }
    path:=filepath.Join(stateDir,"home-signal-recovery.json")
    var previous []time.Time
    data,err:=os.ReadFile(path)
    if err!=nil && !os.IsNotExist(err) { return false }
    if len(data)>0 && json.Unmarshal(data,&previous)!=nil { return false }
    recent:=make([]time.Time,0,3)
    for _,t:=range previous {if now.Sub(t)<time.Hour {recent=append(recent,t)}}
    if len(recent)>=3 { return false }
    for _,t:=range recent {if now.Sub(t)<10*time.Minute {return false}}
    recent=append(recent,now.UTC())
    data,err=json.Marshal(recent);if err!=nil{return false}
    if os.WriteFile(path+".tmp",data,0600)!=nil{return false}
    return os.Rename(path+".tmp",path)==nil
}

func (c *GrpcClient) observeHomeSignalHealth(err error) {
    if runtime.GOOS!="windows" || os.Getenv("NB_HOME_SIGNAL_RECOVERY")!="true" { return }
    c.homeRecovery.observe(c.ctx,err,time.Now(),func(ctx context.Context) error {
        var transport grpc.DialOption
        if c.homeTLS {transport=grpc.WithTransportCredentials(credentials.NewTLS(&tls.Config{MinVersion:tls.VersionTLS12}))}else{transport=grpc.WithTransportCredentials(insecure.NewCredentials())}
        // Independent standard dialer/connection, not the possibly stale client transport.
        fresh,dialErr:=grpc.DialContext(ctx,c.signalConn.Target(),transport,grpc.WithBlock())
        if dialErr!=nil{return dialErr};defer fresh.Close()
        _,sendErr:=proto.NewSignalExchangeClient(fresh).Send(ctx,&proto.EncryptedMessage{Key:c.key.PublicKey().String(),RemoteKey:"dummy"})
        return sendErr
    },func(){
        if !reserveHomeSignalRestart(os.Getenv("NB_STATE_DIR"),time.Now()) {log.Warn("Home Signal recovery skipped: restart budget unavailable or exhausted");return}
        log.Error("Home Signal transport is stuck while an independent RPC succeeds; exiting for bounded Windows service recovery")
        os.Exit(75)
    })
}
