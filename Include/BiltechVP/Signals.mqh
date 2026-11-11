#ifndef BILTECH_VP_SIGNALS_MQH
#define BILTECH_VP_SIGNALS_MQH
#include "Types.mqh"

struct BVPExcursion
{
 bool active,armed; int age; double extreme;
};
struct BVPBreakout
{
 int stage,age; double breakout_extreme,retest_extreme,stop_extreme,atr,buffer;
};

// Input is one newly completed Bid candle at a time, in ascending order.
// No forming candle, future candle or retrospectively selected swing is used.
class CBVPSignals
{
private:
 BVPSignalConfig m_cfg; double m_tick; int m_period;
 BVPExcursion m_a[2]; BVPBreakout m_b[2];
 datetime m_last_bar,m_reference; string m_status;

 void ClearExcursion(const int i)
 { m_a[i].active=false; m_a[i].armed=true; m_a[i].age=0; m_a[i].extreme=0; }
 void ClearBreakout(const int i)
 { ZeroMemory(m_b[i]); }
 void Candidate(const ENUM_SETUP setup,const int direction,const MqlRates &bar,
                const double atr,const double buffer,const double stop,
                const BVPProfile &profile,BVPSignal &out)
 {
  // Process every setup's state even when a higher-priority candidate won.
  // Equal-priority direction ties resolve long first, deterministically.
  if(out.valid && (int)out.setup<=(int)setup) return;
  out.valid=true; out.setup=setup; out.direction=direction;
  out.bar_time=bar.time; out.expires_broker=bar.time+2*m_period;
  out.close=bar.close; out.atr=atr; out.buffer=buffer; out.stop=stop;
  out.poc=profile.poc; out.vah=profile.vah; out.val=profile.val;
  out.id=StringFormat("%I64d:%I64d:%d:%d",(long)profile.start_utc,
                      (long)bar.time,(int)setup,direction);
 }
 void Reentry(const int i,const MqlRates &bar,const double atr,const double buffer,
              const bool atr_valid,const BVPProfile &p,BVPSignal &out)
 {
  const int direction=(i==0 ? 1 : -1);
  const bool inside=(bar.close>=p.val && bar.close<=p.vah);
  const bool strict_inside=(bar.close>p.val && bar.close<p.vah);
  const bool outside=(direction==1 ? bar.close<p.val : bar.close>p.vah);
  if(m_a[i].active)
  {
   m_a[i].age++;
   m_a[i].extreme=(direction==1 ? MathMin(m_a[i].extreme,bar.low)
                                             : MathMax(m_a[i].extreme,bar.high));
   if(strict_inside)
   {
    if(atr_valid)
     Candidate(VALUE_REENTRY,direction,bar,atr,buffer,
               m_a[i].extreme-direction*buffer,p,out);
    // This confirmation is consumed even if ATR is unavailable or priority lost.
    ClearExcursion(i); return;
   }
   if(m_a[i].age>=m_cfg.reentry_bars)
   {
    m_a[i].active=false; m_a[i].armed=false;
    // The expiry bar cannot itself rearm the expired excursion.
   }
   return;
  }
  if(!m_a[i].armed)
  {
   if(inside) m_a[i].armed=true;
   return;
  }
  if(outside)
  {
   m_a[i].active=true; m_a[i].age=0;
   m_a[i].extreme=(direction==1 ? bar.low : bar.high);
  }
 }
 void Breakout(const int i,const MqlRates &bar,const MqlRates &previous,
               const double atr,const double buffer,const bool atr_valid,
               const BVPProfile &p,BVPSignal &out)
 {
  const int direction=(i==0 ? 1 : -1);
  const double level=(direction==1 ? p.vah : p.val);
  if(m_b[i].stage==0)
  {
   if(!atr_valid) return;
   const double threshold=level+direction*buffer;
   const bool crossed=(direction==1 ? bar.close>threshold && previous.close<=threshold
                                   : bar.close<threshold && previous.close>=threshold);
   if(crossed)
   {
    m_b[i].stage=1; m_b[i].age=0;
    m_b[i].breakout_extreme=(direction==1 ? bar.high : bar.low);
    m_b[i].atr=atr; m_b[i].buffer=buffer;
   }
   return; // Breakout, retest and confirmation must be different candles.
  }
  const double frozen_buffer=m_b[i].buffer;
  const bool invalid=(direction==1 ? bar.close<level-frozen_buffer
                                  : bar.close>level+frozen_buffer);
  if(invalid) { ClearBreakout(i); return; }
  m_b[i].age++;
  if(m_b[i].stage==1)
  {
   const bool touches=(bar.low<=level+frozen_buffer && bar.high>=level-frozen_buffer);
   const bool holds=(direction==1 ? bar.close>level : bar.close<level);
   if(touches && holds)
   {
    m_b[i].stage=2; m_b[i].age=0;
    m_b[i].retest_extreme=(direction==1 ? bar.high : bar.low);
    m_b[i].stop_extreme=(direction==1 ? bar.low : bar.high);
    return;
   }
   if(m_b[i].age>=m_cfg.retest_bars) ClearBreakout(i);
   return;
  }
  m_b[i].stop_extreme=(direction==1 ? MathMin(m_b[i].stop_extreme,bar.low)
                                  : MathMax(m_b[i].stop_extreme,bar.high));
  const double threshold=(direction==1 ? MathMax(m_b[i].breakout_extreme,m_b[i].retest_extreme)
                                      : MathMin(m_b[i].breakout_extreme,m_b[i].retest_extreme));
  const bool confirms=(direction==1 ? bar.close>threshold : bar.close<threshold);
  if(confirms)
  {
   Candidate(BREAKOUT_CONTINUATION,direction,bar,m_b[i].atr,frozen_buffer,
             m_b[i].stop_extreme-direction*frozen_buffer,p,out);
   ClearBreakout(i); return;
  }
  if(m_b[i].age>=m_cfg.confirmation_bars) ClearBreakout(i);
 }
 void Bounce(const MqlRates &bar,const MqlRates &previous,const double atr,
             const double buffer,const BVPProfile &p,BVPSignal &out)
 {
  const double lower=p.poc-buffer,upper=p.poc+buffer;
  if(bar.low>upper || bar.high<lower) return;
  if(p.previous_close>p.vah && previous.close>upper && bar.close>upper && bar.close>bar.open)
   Candidate(POC_BOUNCE,1,bar,atr,buffer,bar.low-buffer,p,out);
  if(p.previous_close<p.val && previous.close<lower && bar.close<lower && bar.close<bar.open)
   Candidate(POC_BOUNCE,-1,bar,atr,buffer,bar.high+buffer,p,out);
 }
 string ExcursionStatus(const int i)
 {
  if(m_a[i].active) return StringFormat("excursion %d/%d",m_a[i].age,m_cfg.reentry_bars);
  return (m_a[i].armed ? "armed" : "expired: awaiting inside bar");
 }
 string BreakoutStatus(const int i)
 {
  if(m_b[i].stage==0) return "armed";
  return StringFormat("%s %d/%d",(m_b[i].stage==1 ? "retest" : "confirmation"),m_b[i].age,
                      (m_b[i].stage==1 ? m_cfg.retest_bars : m_cfg.confirmation_bars));
 }
public:
 void Init(const BVPSignalConfig &cfg,const double tick_size,const int period_seconds)
 {
  m_cfg=cfg; m_tick=tick_size; m_period=period_seconds; Reset();
 }
 void Reset()
 {
  for(int i=0;i<2;i++) { ClearExcursion(i); ClearBreakout(i); }
  m_last_bar=0; m_reference=0; m_status="Waiting for completed bar";
 }
 void OnBar(const MqlRates &bar,const MqlRates &previous,const double atr,
            const BVPProfile &profile,BVPSignal &out)
 {
  ZeroMemory(out);
  if(!profile.valid || !BVPFinitePositive(m_tick) || m_period<=0)
  { m_status="Invalid profile, tick size or signal period"; return; }
  if(profile.start_utc!=m_reference) { Reset(); m_reference=profile.start_utc; }
  if(bar.time<=m_last_bar) { m_status="Duplicate or nonascending bar ignored"; return; }
  if(previous.time>=bar.time || !BVPFinitePositive(bar.close) || bar.high<bar.low)
  { m_status="Invalid completed Bid candle"; return; }
  m_last_bar=bar.time;
  const bool atr_valid=BVPFinitePositive(atr);
  const double buffer=MathMax(2*m_tick,(atr_valid ? m_cfg.buffer_atr*atr : 0));
  if(m_cfg.enable_reentry && profile.previous_close>=profile.val && profile.previous_close<=profile.vah)
   for(int i=0;i<2;i++) Reentry(i,bar,atr,buffer,atr_valid,profile,out);
  if(m_cfg.enable_breakout)
   for(int i=0;i<2;i++) Breakout(i,bar,previous,atr,buffer,atr_valid,profile,out);
  if(m_cfg.enable_bounce && atr_valid) Bounce(bar,previous,atr,buffer,profile,out);
  m_status=StringFormat("A %s: L %s; S %s | B %s: L %s; S %s | C %s%s",
   (m_cfg.enable_reentry ? "ON" : "OFF"),ExcursionStatus(0),ExcursionStatus(1),
   (m_cfg.enable_breakout ? "ON" : "OFF"),BreakoutStatus(0),BreakoutStatus(1),
   (m_cfg.enable_bounce ? "ON" : "OFF"),(atr_valid ? "" : " | ATR unavailable"));
 }
 string Status() { return m_status; }
};
#endif
