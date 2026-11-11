#ifndef BILTECH_VP_AUDIT_MQH
#define BILTECH_VP_AUDIT_MQH
#include "TimeProfile.mqh"
#include "Execution.mqh"
class CBVPAudit
{
private:
 int m_file,m_equity_file; string m_symbol,m_parameter,m_scope; long m_magic; ENUM_PROFILE_MODE m_mode;
 double m_last_equity; datetime m_equity_time;
 CBVPClock *m_clock;
 string F(double x) { return MathIsValidNumber(x) && x!=EMPTY_VALUE?DoubleToString(x,8):""; }
 string C(string s) { StringReplace(s,"\"","\"\""); StringReplace(s,"\r"," "); StringReplace(s,"\n"," "); return "\""+s+"\""; }
 double InitialRisk(ulong id,double original_stop)
 {
  if(!BVPFinitePositive(original_stop) || !HistorySelectByPosition(id)) return 0;
  double total=0;
  for(int i=0;i<HistoryDealsTotal();i++)
  {
   ulong deal=HistoryDealGetTicket(i);
   if(HistoryDealGetInteger(deal,DEAL_MAGIC)!=m_magic || (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY)!=DEAL_ENTRY_IN) continue;
   ENUM_DEAL_TYPE type=(ENUM_DEAL_TYPE)HistoryDealGetInteger(deal,DEAL_TYPE);
   if(type!=DEAL_TYPE_BUY && type!=DEAL_TYPE_SELL) continue;
   double loss=0;
   if(!OrderCalcProfit(type==DEAL_TYPE_BUY?ORDER_TYPE_BUY:ORDER_TYPE_SELL,m_symbol,HistoryDealGetDouble(deal,DEAL_VOLUME),HistoryDealGetDouble(deal,DEAL_PRICE),original_stop,loss)) return 0;
   total+=MathMax(0,-loss)+MathMax(0,-HistoryDealGetDouble(deal,DEAL_COMMISSION))+MathMax(0,-HistoryDealGetDouble(deal,DEAL_FEE));
  }
  return total;
 }
public:
 CBVPAudit() { m_file=INVALID_HANDLE; m_equity_file=INVALID_HANDLE; m_last_equity=0; m_equity_time=0; }
 bool Init(string symbol,long magic,string parameter,ENUM_PROFILE_MODE mode,CBVPClock &clock)
 {
  m_file=INVALID_HANDLE; m_symbol=symbol; m_magic=magic; m_parameter=parameter; m_mode=mode; m_clock=GetPointer(clock);
  string identity=(string)AccountInfoInteger(ACCOUNT_LOGIN)+"|"+AccountInfoString(ACCOUNT_SERVER)+"|"+(string)magic;
  string run=(bool)MQLInfoInteger(MQL_TESTER)?"_test_"+(string)TimeLocal()+"_"+(string)GetMicrosecondCount():"";
  m_scope="BVA."+(string)BVPHash(identity+run)+".";
  string filename=StringFormat("BiltechVP_%u_%I64d_%s%s.csv",BVPHash(symbol),magic,parameter,run);
  m_file=FileOpen(filename,FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',');
  if(m_file==INVALID_HANDLE) return false;
  if(FileSize(m_file)==0)
   FileWrite(m_file,"event","signal_trade_id","version","parameter_id","symbol","magic","setup","direction","profile_mode","broker_time","utc_time","new_york_time","profile_start_utc","signal_close","poc","vah","val","atr","buffer","entry","sl","tp","volume","planned_risk_account_ccy","deal_pl_net","realized_R_contribution","spread","commission","swap","fee","slippage_price_signed_adverse","order","deal","position_id","reason","initial_filled_stop_risk_account_ccy");
  FileSeek(m_file,0,SEEK_END); FileFlush(m_file);
  m_equity_file=FileOpen(StringFormat("BiltechVP_%u_%I64d_%s%s_equity.csv",BVPHash(symbol),magic,parameter,run),FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',');
  if(m_equity_file==INVALID_HANDLE) return false;
  if(FileSize(m_equity_file)==0) FileWrite(m_equity_file,"broker_time","utc_time","account_equity","group_daily_pl","group_open_planned_risk");
  FileSeek(m_equity_file,0,SEEK_END); return true;
 }
 void Close() { if(m_file!=INVALID_HANDLE) FileClose(m_file); if(m_equity_file!=INVALID_HANDLE) FileClose(m_equity_file); m_file=INVALID_HANDLE; m_equity_file=INVALID_HANDLE; }
 void Equity(datetime broker,double daily,double risk)
 {
  if(m_equity_file==INVALID_HANDLE) return;
  double equity=AccountInfoDouble(ACCOUNT_EQUITY); if(equity==m_last_equity && broker-m_equity_time<60) return;
  datetime utc=0; m_clock.BrokerToUTC(broker,utc);
  FileWrite(m_equity_file,TimeToString(broker,TIME_DATE|TIME_SECONDS),utc>0?TimeToString(utc,TIME_DATE|TIME_SECONDS):"",DoubleToString(equity,8),DoubleToString(daily,8),DoubleToString(risk,8));
  FileFlush(m_equity_file); m_last_equity=equity; m_equity_time=broker;
 }
 void Row(string event,string reason,const BVPSignal &s,const BVPProfile &p,datetime broker,double entry=0,double sl=0,double tp=0,double volume=0,double risk=0,double pl=0,double commission=0,double swap=0,double fee=0,double slippage=0,ulong order=0,ulong deal=0,ulong pos=0,double rr=EMPTY_VALUE,double actualrisk=EMPTY_VALUE)
 {
  if(m_file==INVALID_HANDLE) return;
  datetime utc=0,ny=0;
  if(m_clock.BrokerToUTC(broker,utc)) ny=m_clock.UTCToNY(utc);
  MqlTick q; double spread=0; if(SymbolInfoTick(m_symbol,q)) spread=q.ask-q.bid;
  FileWrite(m_file,C(event),C(s.id),BVP_VERSION,C(m_parameter),C(m_symbol),m_magic,BVPSetupName(s.setup),s.direction,C(BVPModeName(m_mode)),TimeToString(broker,TIME_DATE|TIME_SECONDS),utc>0?TimeToString(utc,TIME_DATE|TIME_SECONDS):"",ny>0?TimeToString(ny,TIME_DATE|TIME_SECONDS):"",p.start_utc>0?TimeToString(p.start_utc,TIME_DATE|TIME_SECONDS):"",F(s.close),F(s.poc),F(s.vah),F(s.val),F(s.atr),F(s.buffer),F(entry),F(sl),F(tp),F(volume),F(risk),F(pl),F(rr),F(spread),F(commission),F(swap),F(fee),F(slippage),order,deal,pos,C(reason),F(actualrisk));
  FileFlush(m_file);
 }
 void Deal(ulong deal,const BVPProfile &p,CBVPExecution &execution)
 {
  if(deal==0 || GlobalVariableCheck(m_scope+"deal."+(string)deal) || !HistoryDealSelect(deal)) return;
  ulong pos=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
  string symbol=HistoryDealGetString(deal,DEAL_SYMBOL);
  if(symbol!=m_symbol) return;
  if(!execution.OwnedDeal(deal) || !HistoryDealSelect(deal)) return;
  ENUM_DEAL_TYPE type=(ENUM_DEAL_TYPE)HistoryDealGetInteger(deal,DEAL_TYPE);
  if(type!=DEAL_TYPE_BUY && type!=DEAL_TYPE_SELL) return;
  double price=HistoryDealGetDouble(deal,DEAL_PRICE),volume=HistoryDealGetDouble(deal,DEAL_VOLUME);
  double comm=HistoryDealGetDouble(deal,DEAL_COMMISSION),swap=HistoryDealGetDouble(deal,DEAL_SWAP),fee=HistoryDealGetDouble(deal,DEAL_FEE);
  double pl=HistoryDealGetDouble(deal,DEAL_PROFIT)+comm+swap+fee;
  datetime broker=(datetime)HistoryDealGetInteger(deal,DEAL_TIME);
  ENUM_DEAL_ENTRY en=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY);
  ulong order=(ulong)HistoryDealGetInteger(deal,DEAL_ORDER);
  double sl=0,tp=0,requested=0;
  string comment=HistoryDealGetString(deal,DEAL_COMMENT);
  if(HistoryOrderSelect(order))
  { sl=HistoryOrderGetDouble(order,ORDER_SL); tp=HistoryOrderGetDouble(order,ORDER_TP); requested=HistoryOrderGetDouble(order,ORDER_PRICE_OPEN); if(comment=="") comment=HistoryOrderGetString(order,ORDER_COMMENT); }
  BVPSignal s; ZeroMemory(s); double planned=0;
  if(!execution.PositionMetadata(pos,s,planned)) return; // Bare magic cannot prove opening ownership.
  double tick_size=SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_SIZE);
  if(!BVPFinitePositive(tick_size)) return;
  double original_stop=s.direction>0?BVPTickFloor(s.stop,tick_size):BVPTickCeil(s.stop,tick_size);
  if(sl<=0) sl=original_stop;
  string riskkey=m_scope+"r."+(string)pos;
  double risk=InitialRisk(pos,original_stop);
  if(risk>0) GlobalVariableSet(riskkey,risk);
  else if(GlobalVariableCheck(riskkey)) risk=GlobalVariableGet(riskkey);
  // Additive deal contributions use initial lifecycle risk; never invent R without denominator.
  double rr=risk>0 && en!=DEAL_ENTRY_IN?pl/risk:EMPTY_VALUE;
  double slip=requested>0?(price-requested)*(type==DEAL_TYPE_BUY?1:-1):0;
  if(!HistoryDealSelect(deal)) return;
  Row(en==DEAL_ENTRY_IN?"FILL":"EXIT_DEAL",EnumToString((ENUM_DEAL_REASON)HistoryDealGetInteger(deal,DEAL_REASON)),s,p,broker,price,sl,tp,volume,planned,pl,comm,swap,fee,slip,order,deal,pos,rr,risk);
  GlobalVariableSet(m_scope+"deal."+(string)deal,1);
 }
 void Reconcile(const BVPProfile &p,CBVPExecution &execution)
 {
  if(!HistorySelect(0,TimeCurrent()+60)) return;
  ulong tickets[]; int n=HistoryDealsTotal(); ArrayResize(tickets,n);
  for(int i=0;i<n;i++) tickets[i]=HistoryDealGetTicket(i);
  for(int i=0;i<n;i++) Deal(tickets[i],p,execution);
 }
};
#endif
