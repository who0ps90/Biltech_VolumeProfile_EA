#property strict
#property version "1.00"
#property description "Previous completed NY-session profile research EA. No performance claims."
#include "Include/BiltechVP/Types.mqh"
#include "Include/BiltechVP/TimeProfile.mqh"
#include "Include/BiltechVP/Signals.mqh"
#include "Include/BiltechVP/Execution.mqh"
#include "Include/BiltechVP/News.mqh"
#include "Include/BiltechVP/Audit.mqh"

input group "Identity and research preset"
input ENUM_ASSET_PRESET AssetPreset=ASSET_UNSELECTED;
input long StrategyGroupID=26001;
input long InstanceMagic=2600101;
input string ParameterID="baseline-v1";
input bool AllowLiveTrading=false;
input ENUM_TIMEFRAMES SignalTimeframe=PERIOD_M5;
input int ATRPeriod=14;
input group "Clock: configure from verified broker history"
input ENUM_BROKER_CLOCK BrokerTimeMode=BROKER_TIME_UNKNOWN;
input int BrokerBaseUTCOffsetMinutes=0;
input int BrokerDSTDeltaMinutes=60;
input string BrokerOffsetCSV="";
input string HolidayOverrideCSV="";
input int MaximumSessionLookbackDays=14;
input bool UseCustomNYWindows=false;
input string CustomReferenceStartNY="09:30";
input string CustomReferenceEndNY="16:00";
input string CustomEntryStartNY="09:45";
input string CustomEntryEndNY="11:30";
input group "Profile data: no automatic fallback"
input ENUM_PROFILE_MODE ProfileMode=QUOTE_TICK_PROFILE;
input int RequestedRows=60;
input double ValueAreaPercent=70.0;
input int ProfileChunkSeconds=60;
input int MaximumChunkTicks=65536;
input int MaximumProfileEvents=2000000;
input int HistoryRetries=3;
input int MinimumProfileEvents=100;
input double MinimumCoveragePercent=100.0;
input int MaximumCoverageGapMinutes=0;
input group "Setups and completed-bar signals"
input bool EnableValueReentry=true;
input bool EnableBreakoutContinuation=false;
input bool EnablePOCBounce=false;
input bool ReentryPOCSpaceFilter=true;
input int ReentryConfirmationBars=3;
input int BreakoutRetestBars=6;
input int BreakoutConfirmationBars=3;
input double BufferATRFraction=0.10;
input double TargetR=2.0;
input group "Risk: account currency, percentages of equity"
input double RiskPerTradePercent=0.25;
input double MaximumGroupOpenRiskPercent=0.50;
input double MaximumGroupDailyLossPercent=1.00;
input int MaximumGroupConsecutiveLosses=3;
input int MaximumFilledEntriesPerSymbolNYDay=2;
input int MaximumFilledEntriesPerSetupDirectionNYDay=1;
input bool CloseGroupOnDailyLoss=true;
input double EstimatedCommissionPerLotRoundTurn=0.0;
input double EstimatedAdverseSlippageTicks=2.0;
input double FillRiskTolerancePercent=5.0;
input group "Execution filters"
input double MaximumSpreadATRFraction=0.10;
input double MaximumSpreadStopFraction=0.15;
input double MaximumEntryDriftATR=0.20;
input int MaximumQuoteAgeSeconds=10;
input int MaximumDeviationPoints=20;
input group "USD news: required by default"
input ENUM_NEWS_MODE NewsMode=NEWS_MT5_CALENDAR;
input string HistoricalNewsCSV="";
input int NewsMinutesBefore=15;
input int NewsMinutesAfter=15;
input bool EnableFOMCWindow=true;
input int FOMCMinutesBefore=30;
input int FOMCMinutesAfter=30;
input bool AllowSyntheticNewsFixtures=false;

CBVPClock g_clock; CBVPProfileLoader g_loader; CBVPSignals g_signals;
CBVPExecution g_execution; CBVPNews g_news; CBVPAudit g_audit;
BVPProfile g_profile,g_candidate; BVPSignal g_pending;
bool g_clock_ok=false,g_execution_ok=false,g_audit_ok=false,g_search_done=false;
datetime g_bar=0,g_nyday=0,g_search_key=0,g_last_profile_check=0;
int g_atr=INVALID_HANDLE,g_period=0,g_candidate_index=0;
double g_last_atr=0; string g_block="Initializing",g_profile_reason="",g_objects="";
string g_last_skip_id="",g_last_skip_reason="";

bool ParseMinute(string value,int &minute)
{
 string p[]; if(StringSplit(value,':',p)!=2 || StringLen(p[0])!=2 || StringLen(p[1])!=2) return false;
 for(int i=0;i<StringLen(value);i++) if(i!=2 && (StringGetCharacter(value,i)<'0' || StringGetCharacter(value,i)>'9')) return false;
 int h=(int)StringToInteger(p[0]),m=(int)StringToInteger(p[1]);
 if(h<0 || h>23 || m<0 || m>59) return false; minute=h*60+m; return true;
}
datetime BrokerNow() { return (bool)MQLInfoInteger(MQL_TESTER)?TimeCurrent():TimeTradeServer(); }
bool Context(datetime broker,datetime &utc,datetime &nyday,datetime &daystart)
{
 string reason;
 if(!g_clock_ok || !g_clock.BrokerToUTC(broker,utc) || !g_clock.DayContext(utc,nyday,daystart,reason))
 { g_block="Clock invalid: "+g_clock.Status()+" "+reason; return false; }
 return true;
}
void Level(string suffix,double price,color col)
{
 if(!BVPFinitePositive(price)) return;
 string name=g_objects+suffix;
 if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_HLINE,0,0,price);
 ObjectSetDouble(0,name,OBJPROP_PRICE,price); ObjectSetInteger(0,name,OBJPROP_COLOR,col);
 ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_DASH); ObjectSetString(0,name,OBJPROP_TEXT,suffix);
}
void DrawProfile()
{ if(!g_profile.valid) return; Level("POC",g_profile.poc,clrGold); Level("VAH",g_profile.vah,clrDodgerBlue); Level("VAL",g_profile.val,clrDodgerBlue); }
void DrawDeal(ulong deal)
{
 if(!HistoryDealSelect(deal) || HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol || HistoryDealGetInteger(deal,DEAL_MAGIC)!=InstanceMagic) return;
 if(!g_execution.OwnedDeal(deal) || !HistoryDealSelect(deal)) return;
 if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY)!=DEAL_ENTRY_IN) return;
 ENUM_DEAL_TYPE type=(ENUM_DEAL_TYPE)HistoryDealGetInteger(deal,DEAL_TYPE);
 if(type!=DEAL_TYPE_BUY && type!=DEAL_TYPE_SELL) return;
 datetime time=(datetime)HistoryDealGetInteger(deal,DEAL_TIME); double price=HistoryDealGetDouble(deal,DEAL_PRICE);
 ulong pos=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID),order=(ulong)HistoryDealGetInteger(deal,DEAL_ORDER);
 BVPSignal metadata; double planned=0; if(!g_execution.PositionMetadata(pos,metadata,planned)) return;
 string name=g_objects+"ENTRY."+(string)deal;
 if(ObjectFind(0,name)<0) ObjectCreate(0,name,type==DEAL_TYPE_BUY?OBJ_ARROW_BUY:OBJ_ARROW_SELL,0,time,price);
 ObjectSetString(0,name,OBJPROP_TOOLTIP,"EA fill "+(string)pos+" / deal "+(string)deal);
 if(HistoryOrderSelect(order)) { Level("SL."+(string)pos,HistoryOrderGetDouble(order,ORDER_SL),clrTomato); Level("TP."+(string)pos,HistoryOrderGetDouble(order,ORDER_TP),clrLimeGreen); }
}
void DrawOpenProtection()
{
 for(int i=PositionsTotal()-1;i>=0;i--)
 {
  ulong ticket=PositionGetTicket(i);
  if(ticket==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol || PositionGetInteger(POSITION_MAGIC)!=InstanceMagic) continue;
  BVPSignal metadata; double planned=0;
  if(!g_execution.PositionMetadata((ulong)PositionGetInteger(POSITION_IDENTIFIER),metadata,planned) || !PositionSelectByTicket(ticket)) continue;
  string id=(string)PositionGetInteger(POSITION_IDENTIFIER);
  Level("SL."+id,PositionGetDouble(POSITION_SL),clrTomato); Level("TP."+id,PositionGetDouble(POSITION_TP),clrLimeGreen);
 }
}
void Dashboard(datetime broker)
{
 datetime utc=0,ny=0; if(g_clock_ok && g_clock.BrokerToUTC(broker,utc)) ny=g_clock.UTCToNY(utc);
 MqlTick q; ZeroMemory(q); SymbolInfoTick(_Symbol,q); string newsreason; bool newsok=utc>0 && g_news.Allowed(utc,newsreason);
 string text="Biltech Volume Profile EA "+BVP_VERSION+" | "+EnumToString(AssetPreset)+" | "+_Symbol+"\n";
 text+="Broker "+TimeToString(broker,TIME_DATE|TIME_SECONDS)+" | NY "+(ny>0?TimeToString(ny,TIME_DATE|TIME_SECONDS):"UNKNOWN")+" | Malaysia "+(utc>0?TimeToString(utc+8*3600,TIME_DATE|TIME_SECONDS):"UNKNOWN")+"\n";
 text+=BVPModeName(ProfileMode)+"\nProfile: "+(g_loader.Busy()?g_loader.Status():g_profile_reason)+"\n";
 if(g_profile.valid)
 {
  text+="Reference UTC ["+TimeToString(g_profile.start_utc,TIME_DATE|TIME_MINUTES)+", "+TimeToString(g_profile.end_utc,TIME_DATE|TIME_MINUTES)+")\n";
  text+=StringFormat("POC %.8f | VAH %.8f | VAL %.8f | close %.8f\nrows %d width %.8f | events %I64d | coverage %d/%d | gaps %d\n",g_profile.poc,g_profile.vah,g_profile.val,g_profile.previous_close,g_profile.rows,g_profile.bin_width,g_profile.events,g_profile.covered_minutes,g_profile.expected_minutes,g_profile.gap_minutes);
 }
 text+=StringFormat("Setups A=%s B=%s C=%s | %s\n",EnableValueReentry?"ON":"OFF",EnableBreakoutContinuation?"ON":"OFF",EnablePOCBounce?"ON":"OFF",g_signals.Status());
 text+=StringFormat("Spread %.8f | completed ATR %.8f | proposed risk %.2f %s\nGroup daily P/L %.2f | open planned risk %.2f\n",q.ask-q.bid,g_last_atr,g_execution.ProposedRisk(),AccountInfoString(ACCOUNT_CURRENCY),g_execution.DailyPL(),g_execution.OpenRisk());
 text+="News: "+(newsok?g_news.Status():newsreason)+"\nSession: "+(utc>0?(g_clock.EntryWindow(utc)?"entry window open":"entry window closed"):"unknown")+"\n";
 text+="Entry status: "+g_block+"\nExecution: "+g_execution.Status();
 if(NewsMode==NEWS_DISABLED_RESEARCH) text+="\nRESEARCH LABEL: NEWS DISABLED";
 Comment(text);
}
void Audit(string event,string reason,const BVPSignal &s)
{ g_audit.Row(event,reason,s,g_profile,BrokerNow()); }
void BeginCandidate(datetime utc)
{
 string reason; BVPProfile newest; ZeroMemory(newest);
 if(!g_clock.PreviousSession(utc,0,newest,reason)) { g_profile_reason=reason; g_profile.valid=false; return; }
 // Session key stays fixed while trying older complete candidates.
 if(g_search_key==newest.start_utc) return;
 g_search_key=newest.start_utc; g_candidate_index=0; g_search_done=false; g_profile.valid=false; g_pending.valid=false; g_signals.Reset();
 g_candidate=newest; g_loader.Start(g_candidate); g_profile_reason="Loading most recent eligible reference";
}
void ProfileStep(datetime utc)
{
 if(utc-g_last_profile_check>=60 || g_search_key==0) { g_last_profile_check=utc; BeginCandidate(utc); }
 if(g_search_done || (!g_loader.Busy() && !g_loader.Finished())) return;
 // Native history calls can wait internally: defer them while group risk is open.
 if(g_execution.OpenRisk()!=0) { g_profile_reason="Profile loading paused during group exposure or risk conflict"; return; }
 if(g_loader.Busy()) g_loader.Step(g_clock);
 if(!g_loader.Finished()) return;
 BVPProfile result; ZeroMemory(result);
 if(g_loader.Get(result) && result.valid)
 {
  g_profile=result; g_profile_reason=result.status; g_search_done=true; g_signals.Reset(); g_pending.valid=false; DrawProfile();
  BVPSignal empty; ZeroMemory(empty); Audit("PROFILE_FROZEN",result.status,empty); return;
 }
 string rejected=g_loader.Status(); BVPSignal empty; ZeroMemory(empty); Audit("PROFILE_REJECTED",rejected,empty);
 g_candidate_index++;
 string reason;
 if(g_candidate_index>=MaximumSessionLookbackDays || !g_clock.PreviousSession(utc,g_candidate_index,g_candidate,reason))
 { g_search_done=true; g_profile.valid=false; g_profile_reason="No valid reference: "+rejected+" "+reason; return; }
 g_profile_reason="Rejected candidate: "+rejected+"; trying older eligible session"; g_loader.Start(g_candidate);
}
void CompletedBar(datetime broker,datetime utc)
{
 datetime current=iTime(_Symbol,SignalTimeframe,0); if(current<=0 || current==g_bar) return;
 if(g_bar==0) { g_bar=current; return; } // attach/restart never trades a historical signal
 datetime old=g_bar; g_bar=current;
 if(g_pending.valid) Audit("SIGNAL_EXPIRED","Next signal bar ended before an eligible submission",g_pending);
 g_pending.valid=false;
 if(current!=old+g_period) { g_signals.Reset(); g_block="Signal series gap/reconnect: states reset"; return; }
 if(!g_profile.valid || !g_clock.EntryWindow(utc)) { g_signals.Reset(); return; }
 MqlRates rates[]; ArraySetAsSeries(rates,true);
 double atr[]; ArraySetAsSeries(atr,true);
 if(CopyRates(_Symbol,SignalTimeframe,0,3,rates)!=3 || CopyBuffer(g_atr,0,1,1,atr)!=1 || !BVPFinitePositive(atr[0]))
 { g_signals.Reset(); g_block="Completed signal/ATR history unavailable"; return; }
 if(rates[1].time!=current-g_period || rates[2].time!=current-2*g_period) { g_signals.Reset(); g_block="Nonconsecutive completed bars"; return; }
 datetime barutc;
 if(!g_clock.BrokerToUTC(rates[1].time,barutc) || g_profile.end_utc>barutc)
 { g_signals.Reset(); g_block="Reference was not available when signal bar began"; return; }
 g_last_atr=atr[0];
 g_signals.OnBar(rates[1],rates[2],atr[0],g_profile,g_pending);
 if(g_pending.valid) { g_pending.id=_Symbol+":"+g_pending.id; Audit("SIGNAL",g_signals.Status(),g_pending); }
}
void TryPending(const MqlTick &tick,datetime broker,datetime utc,datetime nyday,datetime daystart)
{
 if(!g_pending.valid) return;
 if(broker>=g_pending.expires_broker) { Audit("SIGNAL_EXPIRED","Next signal bar ended",g_pending); g_pending.valid=false; return; }
 if(!g_profile.valid || !g_clock.EntryWindow(utc)) { g_block="Entry window/profile invalid"; return; }
 string reason;
 if(!g_news.Allowed(utc,reason)) { g_block=reason; return; }
 if(!g_audit_ok) { g_block="CSV audit unavailable; new entries blocked"; return; }
 if(g_execution.Blocked()) { g_block=g_execution.Status(); return; }
 // Submission engine consumes IDs durably before the single request; failed requests are not retried.
 bool sent=g_execution.Submit(g_pending,tick,utc,nyday,daystart,reason);
 if(sent || g_pending.id!=g_last_skip_id || reason!=g_last_skip_reason)
 { Audit(sent?"SUBMISSION_ACCEPTED":"ENTRY_SKIPPED",reason,g_pending); g_last_skip_id=g_pending.id; g_last_skip_reason=reason; }
 g_block=reason; if(sent || g_execution.SignalConsumed(g_pending)) g_pending.valid=false;
}
void Cycle(bool tick_event)
{
 datetime broker=BrokerNow(),utc=0,nyday=0,daystart=0; bool clockok=Context(broker,utc,nyday,daystart);
 if(g_pending.valid && broker>=g_pending.expires_broker) { Audit("SIGNAL_EXPIRED","Next signal bar ended before an eligible submission",g_pending); g_pending.valid=false; }
 if(g_execution_ok) g_execution.Supervise(broker,utc,nyday,daystart,clockok && g_clock.PastEntryEnd(utc));
 if(g_audit_ok) g_audit.Equity(broker,g_execution.DailyPL(),g_execution.OpenRisk());
 if(clockok)
 {
  if(nyday!=g_nyday) { g_nyday=nyday; g_signals.Reset(); g_pending.valid=false; }
  if(tick_event)
  {
   CompletedBar(broker,utc); MqlTick tick;
   if(SymbolInfoTick(_Symbol,tick)) TryPending(tick,broker,utc,nyday,daystart);
  }
  else { g_news.Refresh(utc,g_clock); ProfileStep(utc); }
  if(!g_pending.valid)
  {
   if(!g_audit_ok) g_block="CSV audit unavailable; new entries blocked";
   else if(!g_profile.valid) g_block="Profile unavailable: "+g_profile_reason;
   else if(g_execution.Blocked()) g_block=g_execution.Status();
   else if(!g_clock.EntryWindow(utc)) g_block="Outside New York entry window";
   else { string nr; g_block=g_news.Allowed(utc,nr)?"Ready; waiting for completed-bar setup":nr; }
  }
 }
 if(!tick_event) { DrawOpenProtection(); Dashboard(broker); }
}
int OnInit()
{
 ZeroMemory(g_profile); ZeroMemory(g_pending); ZeroMemory(g_candidate);
 if(AssetPreset<GOLD || AssetPreset>US30 || ProfileMode<QUOTE_TICK_PROFILE || ProfileMode>M1_APPROXIMATION || NewsMode<NEWS_MT5_CALENDAR || NewsMode>NEWS_DISABLED_RESEARCH || BrokerTimeMode<BROKER_TIME_UNKNOWN || BrokerTimeMode>BROKER_OFFSET_SCHEDULE || StrategyGroupID<=0 || InstanceMagic<=0 || StringLen(ParameterID)<1 || StringLen(ParameterID)>32)
 { Print("Select AssetPreset explicitly; positive group and unique magic required; ParameterID length 1..32"); return INIT_PARAMETERS_INCORRECT; }
 for(int i=0;i<StringLen(ParameterID);i++)
 { ushort c=StringGetCharacter(ParameterID,i); if(!((c>='a'&&c<='z')||(c>='A'&&c<='Z')||(c>='0'&&c<='9')||c=='-'||c=='_')) { Print("ParameterID accepts letters digits - _ only"); return INIT_PARAMETERS_INCORRECT; } }
 double finite_inputs[]={ValueAreaPercent,MinimumCoveragePercent,BufferATRFraction,TargetR,RiskPerTradePercent,MaximumGroupOpenRiskPercent,MaximumGroupDailyLossPercent,EstimatedCommissionPerLotRoundTurn,EstimatedAdverseSlippageTicks,FillRiskTolerancePercent,MaximumSpreadATRFraction,MaximumSpreadStopFraction,MaximumEntryDriftATR};
 for(int i=0;i<ArraySize(finite_inputs);i++) if(!MathIsValidNumber(finite_inputs[i])) { Print("Nonfinite numeric input rejected"); return INIT_PARAMETERS_INCORRECT; }
 g_period=PeriodSeconds(SignalTimeframe);
 if(g_period<60 || g_period>86400 || ATRPeriod<2 || RequestedRows<1 || RequestedRows>10000 || ValueAreaPercent<=0 || ValueAreaPercent>100 || MaximumSessionLookbackDays<1 || MaximumSessionLookbackDays>366 || ProfileChunkSeconds<1 || MaximumChunkTicks<1 || MaximumChunkTicks>65536 || MaximumProfileEvents<MinimumProfileEvents || MinimumProfileEvents<1 || MinimumCoveragePercent<=0 || MinimumCoveragePercent>100 || MaximumCoverageGapMinutes<0 || HistoryRetries<1 || ReentryConfirmationBars<1 || BreakoutRetestBars<1 || BreakoutConfirmationBars<1 || BufferATRFraction<0 || TargetR<=0 || RiskPerTradePercent<=0 || MaximumGroupOpenRiskPercent<=0 || MaximumGroupDailyLossPercent<=0 || MaximumGroupConsecutiveLosses<1 || MaximumFilledEntriesPerSymbolNYDay<1 || MaximumFilledEntriesPerSetupDirectionNYDay<1 || EstimatedCommissionPerLotRoundTurn<0 || EstimatedAdverseSlippageTicks<0 || FillRiskTolerancePercent<0 || MaximumSpreadATRFraction<0 || MaximumSpreadStopFraction<0 || MaximumEntryDriftATR<0 || MaximumQuoteAgeSeconds<1 || MaximumDeviationPoints<0 || NewsMinutesBefore<0 || NewsMinutesAfter<0 || FOMCMinutesBefore<0 || FOMCMinutesAfter<0)
 { Print("Invalid parameter range; inspect inputs"); return INIT_PARAMETERS_INCORRECT; }
 if((ENUM_SYMBOL_CHART_MODE)SymbolInfoInteger(_Symbol,SYMBOL_CHART_MODE)!=SYMBOL_CHART_MODE_BID)
 { Print("EA requires Bid-based chart bars; this symbol supplies Last-based bars"); return INIT_FAILED; }
 BVPClockConfig cc; ZeroMemory(cc); cc.mode=BrokerTimeMode; cc.base_offset_minutes=BrokerBaseUTCOffsetMinutes; cc.dst_delta_minutes=BrokerDSTDeltaMinutes;
 cc.offset_file=BrokerOffsetCSV; cc.holiday_file=HolidayOverrideCSV; cc.lookback_days=MaximumSessionLookbackDays;
 cc.reference_start_minute=AssetPreset==GOLD?500:570; cc.reference_end_minute=AssetPreset==GOLD?810:960;
 cc.entry_start_minute=AssetPreset==GOLD?510:585; cc.entry_end_minute=AssetPreset==GOLD?660:690;
 if(UseCustomNYWindows && (!ParseMinute(CustomReferenceStartNY,cc.reference_start_minute) || !ParseMinute(CustomReferenceEndNY,cc.reference_end_minute) || !ParseMinute(CustomEntryStartNY,cc.entry_start_minute) || !ParseMinute(CustomEntryEndNY,cc.entry_end_minute)))
 { Print("Custom NY times must be HH:MM"); return INIT_PARAMETERS_INCORRECT; }
 string reason; g_clock_ok=g_clock.Init(cc,reason); if(!g_clock_ok) Print("Clock setup required: ",reason);
 BVPProfileConfig pc; ZeroMemory(pc); pc.mode=ProfileMode; pc.requested_rows=RequestedRows; pc.value_percent=ValueAreaPercent; pc.chunk_seconds=ProfileChunkSeconds;
 pc.max_chunk_ticks=MaximumChunkTicks; pc.max_events=MaximumProfileEvents; pc.max_retries=HistoryRetries; pc.min_events=MinimumProfileEvents; pc.minimum_coverage_percent=MinimumCoveragePercent; pc.maximum_gap_minutes=MaximumCoverageGapMinutes; g_loader.Init(_Symbol,pc);
 BVPSignalConfig sc; ZeroMemory(sc); sc.enable_reentry=EnableValueReentry; sc.enable_breakout=EnableBreakoutContinuation; sc.enable_bounce=EnablePOCBounce; sc.reentry_space_filter=ReentryPOCSpaceFilter;
 sc.reentry_bars=ReentryConfirmationBars; sc.retest_bars=BreakoutRetestBars; sc.confirmation_bars=BreakoutConfirmationBars; sc.buffer_atr=BufferATRFraction; sc.target_r=TargetR;
 g_signals.Init(sc,SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE),g_period);
 BVPRiskConfig rc; ZeroMemory(rc); rc.group_id=StrategyGroupID; rc.magic=InstanceMagic; rc.allow_live=AllowLiveTrading; rc.close_on_daily_loss=CloseGroupOnDailyLoss;
 rc.risk_percent=RiskPerTradePercent; rc.aggregate_percent=MaximumGroupOpenRiskPercent; rc.daily_loss_percent=MaximumGroupDailyLossPercent; rc.max_losses=MaximumGroupConsecutiveLosses;
 rc.max_symbol_entries=MaximumFilledEntriesPerSymbolNYDay; rc.max_setup_direction_entries=MaximumFilledEntriesPerSetupDirectionNYDay;
 rc.commission_per_lot_round_turn=EstimatedCommissionPerLotRoundTurn; rc.slippage_ticks=EstimatedAdverseSlippageTicks; rc.fill_risk_tolerance_percent=FillRiskTolerancePercent;
 rc.spread_atr_fraction=MaximumSpreadATRFraction; rc.spread_stop_fraction=MaximumSpreadStopFraction; rc.max_entry_drift_atr=MaximumEntryDriftATR;
 rc.quote_max_age_seconds=MaximumQuoteAgeSeconds; rc.deviation_points=MaximumDeviationPoints; rc.parameter_id=ParameterID; rc.target_r=TargetR; rc.reentry_space_filter=ReentryPOCSpaceFilter;
 g_execution_ok=g_execution.Init(_Symbol,rc,reason);
 if(!g_execution_ok) { Print("Execution initialization blocked: ",reason); return INIT_FAILED; }
 g_news.Init(NewsMode,HistoricalNewsCSV,NewsMinutesBefore,NewsMinutesAfter,EnableFOMCWindow,FOMCMinutesBefore,FOMCMinutesAfter,AllowSyntheticNewsFixtures);
 g_audit_ok=g_audit.Init(_Symbol,InstanceMagic,ParameterID,ProfileMode,g_clock);
 if(!g_audit_ok) Print("Audit CSV cannot be opened; entries will remain blocked");
 g_atr=iATR(_Symbol,SignalTimeframe,ATRPeriod);
 if(g_atr==INVALID_HANDLE) { g_execution.Shutdown(); Print("Cannot create ATR handle"); return INIT_FAILED; }
 g_objects=StringFormat("BVP.%I64d.",InstanceMagic); g_bar=iTime(_Symbol,SignalTimeframe,0);
 EventSetTimer(1); Print("BiltechVP ",BVP_VERSION," initialized. ",BVPModeName(ProfileMode),"; live allowed=",AllowLiveTrading,"; parameter=",ParameterID);
 Cycle(false); if(g_audit_ok) g_audit.Reconcile(g_profile,g_execution); return INIT_SUCCEEDED;
}
void OnTick() { Cycle(true); }
void OnTimer() { Cycle(false); }
void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
{
 if(g_execution_ok) g_execution.Transaction(trans,request,result);
 if(trans.type==TRADE_TRANSACTION_DEAL_ADD) { g_audit.Deal(trans.deal,g_profile,g_execution); DrawDeal(trans.deal); }
}
void OnDeinit(const int reason)
{
 EventKillTimer(); if(g_atr!=INVALID_HANDLE) IndicatorRelease(g_atr);
 if(g_execution_ok) g_execution.Shutdown(); g_audit.Close(); if(StringLen(g_objects)>0) ObjectsDeleteAll(0,g_objects); Comment("");
}
