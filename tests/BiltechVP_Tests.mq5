#property strict
#property version "1.00"
#property description "Synthetic deterministic tests; no trading. Production headers are executed."
#include "../Include/BiltechVP/Signals.mqh"
#include "../Include/BiltechVP/TimeProfile.mqh"
#include "../Include/BiltechVP/News.mqh"
#include "../Include/BiltechVP/Execution.mqh"

int g_checks=0,g_failures=0;
const datetime FIXTURE_T0=D'2026.01.05 14:00:00';
void Check(const bool ok,const string label)
{
 g_checks++; if(!ok) { g_failures++; Print("FAIL ",label); }
}
bool Near(const double a,const double b) { return MathAbs(a-b)<1e-7; }
MqlRates FixtureRate(const double o,const double h,const double l,const double c,const datetime t)
{
 MqlRates b={}; b.time=t; b.open=o; b.high=h; b.low=l; b.close=c; b.tick_volume=1; return b;
}
BVPSignalConfig FixtureConfig(const string enabled)
{
 BVPSignalConfig c={}; c.enable_reentry=StringFind(enabled,"A")>=0;
 c.enable_breakout=StringFind(enabled,"B")>=0; c.enable_bounce=StringFind(enabled,"C")>=0;
 c.reentry_space_filter=false; c.reentry_bars=3; c.retest_bars=6; c.confirmation_bars=3;
 c.buffer_atr=0.1; c.target_r=2; return c;
}
BVPProfile FixtureProfile(const double previous_close)
{
 BVPProfile p={}; p.valid=true; p.start_utc=D'2026.01.02 14:30:00';
 p.end_utc=D'2026.01.02 21:00:00'; p.val=100; p.vah=110; p.poc=105;
 p.previous_close=previous_close; return p;
}
void CheckSignal(const BVPSignal &got,const string label,const int setup,const int direction,
                 const double stop,const double atr,const double buffer,const datetime t,const datetime reference)
{
 Check(got.valid==(setup!=0),label+":valid"); if(setup==0 || !got.valid) return;
 Check((int)got.setup==setup && got.direction==direction,label+":setup/direction");
 Check(Near(got.stop,stop),label+":stop"); Check(Near(got.atr,atr),label+":completed/frozen ATR");
 Check(Near(got.buffer,buffer),label+":buffer");
 Check(got.bar_time==t && got.expires_broker==t+600,label+":next-bar expiry");
 Check(got.id==StringFormat("%I64d:%I64d:%d:%d",(long)reference,(long)t,setup,direction),label+":stable identifier");
}
#include "generated_signal_fixtures.mqh"

void TestProductionProfile()
{
 string reason; BVPProfile p={}; double ignored[];
 double prices[]={100,101,102,103,104},weights[]={2,1,1,1,1};
 Check(BVPBuildProfile(prices,weights,ignored,ignored,1,4,70,false,p,reason),"profile final-boundary valid");
 Check(p.rows==4 && Near(p.lower,100) && Near(p.bin_width,1),"profile actual rows/width");
 Check(Near(p.total_weight,6) && Near(p.poc,100.5) && Near(p.val,100) && Near(p.vah,104),"profile max included, outer POC tie lower");
 double centers[]={100.2,101.2,102.2,103.2},tie_weights[]={1,3,3,1};
 Check(BVPBuildProfile(centers,tie_weights,ignored,ignored,1,4,50,false,p,reason),"profile center tie valid");
 Check(Near(p.poc,101.5) && Near(p.val,101) && Near(p.vah,103),"profile POC closest midpoint then lower");
 double va_weights[]={2,4,2,1};
 Check(BVPBuildProfile(centers,va_weights,ignored,ignored,1,4,60,false,p,reason),"profile VA tie valid");
 Check(Near(p.poc,101.5) && Near(p.val,100) && Near(p.vah,102),"profile VA equal adjacent bins lower first");
 double mp[]={101,101},mw[]={10,3},ml[]={100,101},mh[]={102,101};
 Check(BVPBuildProfile(mp,mw,ml,mh,1,2,50,true,p,reason),"M1 overlap/zero range valid");
 Check(Near(p.total_weight,13) && Near(p.poc,101.5) && Near(p.val,101) && Near(p.vah,102),"M1 overlap/zero range expected levels");
 Check(!BVPBuildProfile(ignored,ignored,ignored,ignored,1,60,70,false,p,reason) && !p.valid,"empty history invalid");
 double pp[]={100.12,117.13},ww[]={3,7};
 Check(BVPBuildProfile(pp,ww,ignored,ignored,.25,60,100,false,p,reason),"tick multiple profile valid");
 Check(p.rows<=60 && Near(p.lower,100) && Near(p.bin_width,.5) && Near(p.total_weight,10),"tick alignment and row cap");
}
void TestProductionClock()
{
 Check(BVPUSOffsetMinutes(D'2026.03.08 06:59:59')==-300,"US spring before");
 Check(BVPUSOffsetMinutes(D'2026.03.08 07:00:00')==-240,"US spring at");
 Check(BVPUSOffsetMinutes(D'2026.11.01 05:59:59')==-240,"US fall before");
 Check(BVPUSOffsetMinutes(D'2026.11.01 06:00:00')==-300,"US fall at");
 Check(BVPUSOffsetMinutes(D'2006.03.20 12:00:00')==-300,"historical pre2007 rule");
 Check(BVPUSOffsetMinutes(D'1974.01.06 07:00:00')==-240,"1974 emergency DST");
 Check(BVPUSOffsetMinutes(D'2026.03.16 12:00:00')==-240 && !BVPEUIsDST(D'2026.03.16 12:00:00'),"mismatched spring weeks");
 Check(BVPUSOffsetMinutes(D'2026.10.26 12:00:00')==-240 && !BVPEUIsDST(D'2026.10.26 12:00:00'),"mismatched fall week");
 BVPClockConfig cfg={}; cfg.mode=BROKER_EU_DST; cfg.base_offset_minutes=120; cfg.dst_delta_minutes=60;
 cfg.lookback_days=10; cfg.reference_start_minute=570; cfg.reference_end_minute=960;
 cfg.entry_start_minute=585; cfg.entry_end_minute=690;
 CBVPClock clock; string reason; datetime b,u;
 Check(clock.Init(cfg,reason),"explicit EU broker clock");
 Check(clock.UTCToBroker(D'2026.03.16 12:00:00',b) && b==D'2026.03.16 14:00:00',"EU broker spring mismatch offset");
 Check(clock.UTCToNY(D'2026.03.16 12:00:00')==D'2026.03.16 08:00:00',"NY independent spring mismatch offset");
 Check(clock.UTCToBroker(D'2026.03.30 12:00:00',b) && b==D'2026.03.30 15:00:00',"EU broker after transition");
 Check(clock.BrokerToUTC(b,u) && u==D'2026.03.30 12:00:00',"broker UTC inverse");
 Check(!clock.NYToUTC(D'2026.11.01 01:30:00',u),"ambiguous NY fallback blocked");
 Check(!clock.NYToUTC(D'2026.03.08 02:30:00',u),"nonexistent NY spring blocked");
 Check(clock.EntryWindow(D'2026.01.05 14:45:00'),"entry start included");
 Check(!clock.EntryWindow(D'2026.01.05 16:30:00'),"entry end excluded");
 BVPProfile session={};
 Check(clock.PreviousSession(D'2026.01.05 15:00:00',0,session,reason) && session.ny_date==D'2026.01.02',"Monday skips incomplete today and weekend");
 Check(clock.PreviousSession(D'2026.01.05 21:00:00',0,session,reason) && session.ny_date==D'2026.01.05',"reference end completion inclusive");
 cfg.entry_start_minute=1320; cfg.entry_end_minute=120;
 Check(clock.Init(cfg,reason) && clock.EntryWindow(D'2026.01.06 06:00:00'),"overnight entry previous eligible day");
 Check(!clock.EntryWindow(D'2026.01.06 07:00:00'),"overnight end excluded");
 cfg.mode=BROKER_TIME_UNKNOWN;
 Check(!clock.Init(cfg,reason),"unknown broker clock blocked");
}
void TestSignalReset()
{
 CBVPSignals engine; engine.Init(FixtureConfig("A"),.1,300);
 BVPProfile p=FixtureProfile(105);
 MqlRates previous=FixtureRate(100,100,100,100,FIXTURE_T0-300);
 MqlRates excursion=FixtureRate(100,101,97,99,FIXTURE_T0);
 MqlRates confirmation=FixtureRate(99,103,98,101,FIXTURE_T0+300);
 BVPSignal s; engine.OnBar(excursion,previous,10,p,s);
 engine.Reset(); engine.OnBar(confirmation,excursion,10,p,s);
 Check(!s.valid,"day/restart reset cannot invent old excursion");
 engine.Reset(); engine.OnBar(excursion,previous,10,p,s);
 p.start_utc+=86400; engine.OnBar(confirmation,excursion,10,p,s);
 Check(!s.valid,"new frozen reference resets prior excursion");
}
void TestProductionMissingNews()
{
 CBVPNews news; string reason;
 news.Init(NEWS_HISTORICAL_CSV,"__BVP_deliberately_absent_fixture_712d6cef.csv",15,15,true,30,30,false);
 Check(!news.Allowed(FIXTURE_T0,reason),"actual news class: missing historical CSV blocks");
 news.Init(NEWS_DISABLED_RESEARCH,"",15,15,true,30,30,false);
 Check(news.Allowed(FIXTURE_T0,reason),"actual news class: explicit disabled research mode");
}
void TestProductionTickFilters()
{
 MqlTick tick={}; tick.time_msc=1700000000000; tick.bid=100; tick.flags=TICK_FLAG_BID;
 bool have_bid=false; double previous_bid=0;
 Check(BVPQuoteEvent(tick,have_bid,previous_bid),"first explicitly flagged Bid event counted");
 tick.bid=101;
 Check(BVPQuoteEvent(tick,have_bid,previous_bid),"same millisecond changed Bid event one");
 tick.bid=100;
 Check(BVPQuoteEvent(tick,have_bid,previous_bid),"same millisecond changed Bid event two");
 Check(!BVPQuoteEvent(tick,have_bid,previous_bid),"unchanged Bid snapshot excluded");
 tick.flags=TICK_FLAG_ASK; tick.last=100; tick.volume=7; tick.volume_real=7;
 Check(!BVPQuoteEvent(tick,have_bid,previous_bid),"Ask-only record excluded");
 double price=0,weight=0;
 Check(!BVPTradeEvent(tick,price,weight),"quote-only stale trade volume excluded");
 tick.flags=TICK_FLAG_LAST|TICK_FLAG_VOLUME;
 Check(BVPTradeEvent(tick,price,weight) && Near(price,100) && Near(weight,7),"trade event Last/positive volume");
 Check(BVPTradeEvent(tick,price,weight),"same-ms identical genuine trade event retained");
 tick.volume=0; tick.volume_real=0;
 Check(!BVPTradeEvent(tick,price,weight),"zero trade volume excluded");
 tick.bid=0;
 Check(!BVPQuoteEvent(tick,have_bid,previous_bid) && !have_bid,"invalid Bid cannot bridge comparison state");
}
void TestProductionVolumeFloor()
{
 Check(Near(BVPVolumeFloor(.129,.01),.12),"actual volume helper floors 0.129 to 0.12");
 Check(Near(BVPVolumeFloor(.74,.25),.5),"actual volume helper handles quarter step");
 Check(BVPVolumeFloor(.009,.01)<.01,"actual volume helper does not force minimum lot");
}
int OnInit()
{
 TestProductionProfile(); TestProductionClock(); TestSignalFixtures(); TestSignalReset(); TestProductionMissingNews(); TestProductionTickFilters();
 TestProductionVolumeFloor();
 PrintFormat("BILTECH_NATIVE_RESULT checks=%d failures=%d version=%s",g_checks,g_failures,BVP_VERSION);
 return INIT_SUCCEEDED;
}
void OnTick() {}
double OnTester() { return (g_failures==0 ? (double)g_checks : -(double)g_failures); }
