#ifndef BILTECH_VP_EXECUTION_MQH
#define BILTECH_VP_EXECUTION_MQH
#include "Types.mqh"

double BVPVolumeFloor(const double requested,const double step)
{
 if(!MathIsValidNumber(requested) || requested<0 || !BVPFinitePositive(step)) return 0;
 return NormalizeDouble(MathFloor(requested/step+1e-10)*step,8);
}

// All persistent keys are terminal-global and scoped to account AND server.
// A reservation is a write-ahead record: an indeterminate send never expires.
struct BVPExecLife
{
 ulong id; long magic; string symbol; double signed_volume,net;
 bool seen_in,foreign_in,foreign_any,group_owned;
 datetime first,last; int setup,direction;
};

class CBVPExecution
{
private:
 string m_symbol,m_root,m_group,m_status,m_symbol_key,m_last_skip;
 BVPRiskConfig m_cfg; double m_token,m_mutex,m_daily,m_open,m_proposed;
 datetime m_day,m_day_start,m_broker,m_utc; bool m_ready,m_blocked,m_history_ok;
 BVPExecLife m_life[];

 string N(const long x) { return IntegerToString(x); }
 string M(const string field,const long magic) { return m_root+"."+field+N(magic); }
 string P(const string field,const ulong id) { return m_root+".P"+field+IntegerToString((long)id); }
 string D(const string field) { return m_group+"."+field+N((long)m_day); }
 double G(const string key,const double fallback=0) { return GlobalVariableCheck(key)?GlobalVariableGet(key):fallback; }
 void Put(const string key,const double value)
 {
  GlobalVariableSet(key,value);
  if(key==m_group+".FATAL" && value>0)
  {
   int h=FileOpen(m_group+"_fatal.txt",FILE_WRITE|FILE_TXT|FILE_COMMON|FILE_SHARE_READ);
   if(h!=INVALID_HANDLE) { FileWrite(h,"Persistent protection error. Review positions and journal before manual reset."); FileFlush(h); FileClose(h); }
  }
 }
 string PendingFile(const long magic) { return m_root+"_pending_"+N(magic)+".csv"; }
 string PositionFile(const ulong id) { return m_root+"_position_"+N((long)id)+".csv"; }
 string JournalFile(const long magic) { return m_root+"_active_"+N(magic)+".csv"; }
 bool Journal(const BVPSignal &s,const double risk,const double stop,const double volume)
 {
  int h=FileOpen(JournalFile(m_cfg.magic),FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ,',');
  if(h==INVALID_HANDLE) return false;
  bool ok=FileWrite(h,(long)m_broker,(long)BVPHash(s.id),stop,volume,risk,(long)m_day)>0;
  FileFlush(h); FileClose(h); return ok;
 }
 void RecoverJournal(const long magic)
 {
  if(!FileIsExist(JournalFile(magic),FILE_COMMON)) return;
  int h=FileOpen(JournalFile(magic),FILE_READ|FILE_CSV|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ,',');
  if(h==INVALID_HANDLE) { Put(M("R",magic),DBL_MAX/1000000); return; }
  datetime since=(datetime)StringToInteger(FileReadString(h)); uint hash=(uint)StringToInteger(FileReadString(h));
  double stop=StringToDouble(FileReadString(h)),volume=StringToDouble(FileReadString(h)),risk=StringToDouble(FileReadString(h));
  datetime day=(datetime)StringToInteger(FileReadString(h)); FileClose(h);
  if(since<=0 || stop<=0 || volume<=0 || risk<=0 || day<=0) { Put(M("R",magic),DBL_MAX/1000000); return; }
  Put(M("R",magic),risk); Put(M("T",magic),(double)since); Put(M("I",magic),(double)hash);
  Put(M("K",magic),stop); Put(M("V",magic),volume); Put(M("W",magic),3);
  string group=m_root+".G"+N((long)G(M("M",magic)));
  Put(group+".S"+N((long)day)+"."+N((long)hash),1);
 }
 bool RestoreRegistry()
 {
  string file=m_root+"_registry.csv";
  if(!FileIsExist(file,FILE_COMMON)) return true;
  int h=FileOpen(file,FILE_READ|FILE_CSV|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ,',');
  if(h==INVALID_HANDLE) return false;
  bool ok=true;
  while(!FileIsEnding(h))
  {
   string first=FileReadString(h); if(first=="" && FileIsEnding(h)) break;
   long magic=StringToInteger(first),group=StringToInteger(FileReadString(h));
   string symbol=FileReadString(h);
   double commission=StringToDouble(FileReadString(h)),slippage=StringToDouble(FileReadString(h));
   double target=StringToDouble(FileReadString(h)),tolerance=StringToDouble(FileReadString(h));
   uint policy=(uint)StringToInteger(FileReadString(h));
   if(magic<=0 || group<=0 || symbol=="" || target<=0 || commission<0 || slippage<0 || tolerance<0) { ok=false; break; }
   if(GlobalVariableCheck(M("M",magic)) && (G(M("M",magic))!=(double)group || G(M("Y",magic))!=(double)BVPHash(symbol))) { ok=false; break; }
   Put(M("M",magic),(double)group); Put(M("Y",magic),(double)BVPHash(symbol));
   Put(M("C",magic),commission); Put(M("L",magic),slippage); Put(M("J",magic),target); Put(M("F",magic),tolerance);
   Put(m_root+".G"+N(group)+".POL",(double)policy);
   RecoverJournal(magic);
  }
  FileClose(h); return ok;
 }
 bool SaveRegistry(const uint policy)
 {
  int h=FileOpen(m_root+"_registry.csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ,',');
  if(h==INVALID_HANDLE) return false;
  FileSeek(h,0,SEEK_END);
  bool ok=FileWrite(h,m_cfg.magic,m_cfg.group_id,m_symbol,m_cfg.commission_per_lot_round_turn,m_cfg.slippage_ticks,m_cfg.target_r,m_cfg.fill_risk_tolerance_percent,(long)policy)>0;
  FileFlush(h); FileClose(h); return ok;
 }
 bool SavePending(const BVPSignal &s,const double risk)
 {
  int h=FileOpen(PendingFile(m_cfg.magic),FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ,',');
  if(h==INVALID_HANDLE) return false;
  bool ok=FileWrite(h,(int)s.valid,s.id,(int)s.setup,s.direction,(long)s.bar_time,(long)s.expires_broker,
                   s.close,s.atr,s.buffer,s.stop,s.poc,s.vah,s.val,risk)>0;
  FileFlush(h); FileClose(h); return ok;
 }
 bool ReadMetadata(const string file,BVPSignal &s,double &risk)
 {
  int h=FileOpen(file,FILE_READ|FILE_CSV|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ,',');
  if(h==INVALID_HANDLE) return false;
  s.valid=StringToInteger(FileReadString(h))!=0; s.id=FileReadString(h);
  s.setup=(ENUM_SETUP)StringToInteger(FileReadString(h)); s.direction=(int)StringToInteger(FileReadString(h));
  s.bar_time=(datetime)StringToInteger(FileReadString(h)); s.expires_broker=(datetime)StringToInteger(FileReadString(h));
  s.close=StringToDouble(FileReadString(h)); s.atr=StringToDouble(FileReadString(h));
  s.buffer=StringToDouble(FileReadString(h)); s.stop=StringToDouble(FileReadString(h));
  s.poc=StringToDouble(FileReadString(h)); s.vah=StringToDouble(FileReadString(h)); s.val=StringToDouble(FileReadString(h));
  risk=StringToDouble(FileReadString(h)); FileClose(h); return s.id!="" && risk>0;
 }
 string CSVSafe(string value)
 {
  StringReplace(value,",",";"); StringReplace(value,"\r"," "); StringReplace(value,"\n"," "); StringReplace(value,"\"","'"); return value;
 }
 void Log(const string event,const string reason)
 {
  Print("BVP EXEC ",event," ",m_symbol,": ",reason);
  string file="BiltechVP_execution_"+N(AccountInfoInteger(ACCOUNT_LOGIN))+"_"+N(m_cfg.magic)+".csv";
  int h=FileOpen(file,FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_COMMON,',');
  if(h==INVALID_HANDLE) return;
  if(FileSize(h)==0) FileWrite(h,"version","parameter_id","event","symbol","magic","group","broker","utc","ny_day","reason","proposed_risk","group_open_risk","daily_pl");
  FileSeek(h,0,SEEK_END);
  FileWrite(h,BVP_VERSION,CSVSafe(m_cfg.parameter_id),event,CSVSafe(m_symbol),m_cfg.magic,m_cfg.group_id,
            TimeToString(m_broker,TIME_DATE|TIME_SECONDS),TimeToString(m_utc,TIME_DATE|TIME_SECONDS),
            TimeToString(m_day,TIME_DATE),CSVSafe(reason),DoubleToString(m_proposed,2),DoubleToString(m_open,2),DoubleToString(m_daily,2));
  FileClose(h);
 }
 bool Lock()
 {
  string key=m_root+".X";
  // GlobalVariableTemp creates a missing mutex without overwriting an existing one.
  if(!GlobalVariableCheck(key) && !GlobalVariableTemp(key)) return false;
  for(int i=0;i<5;i++)
  {
   double old=G(key),now=(double)TimeLocal();
   if(old>now) return false;
   m_mutex=now+360.0+(double)(GetMicrosecondCount()%1000)/1000.0;
   if(GlobalVariableSetOnCondition(key,m_mutex,old)) return true;
  }
  return false;
 }
 void Unlock() { if(m_mutex>0) GlobalVariableSetOnCondition(m_root+".X",0,m_mutex); m_mutex=0; }
 bool OwnLease()
 {
  if(G(m_symbol_key)!=m_token) { m_status="Symbol instance lease lost; new entries disabled"; return false; }
  Put(m_symbol_key+"H",(double)TimeLocal()+120); return true;
 }
 bool GroupMagic(const long magic)
 {
  return magic>0 && GlobalVariableCheck(M("M",magic)) && G(M("M",magic))==(double)m_cfg.group_id;
 }
 int LifeIndex(const ulong id)
 {
  for(int i=0;i<ArraySize(m_life);i++) if(m_life[i].id==id) return i;
  int n=ArraySize(m_life); ArrayResize(m_life,n+1);
  m_life[n].id=id; m_life[n].magic=0; m_life[n].symbol=""; m_life[n].signed_volume=0; m_life[n].net=0;
  m_life[n].seen_in=false; m_life[n].foreign_in=false; m_life[n].foreign_any=false;
  m_life[n].group_owned=false; m_life[n].first=0; m_life[n].last=0;
  m_life[n].setup=0; m_life[n].direction=0; return n;
 }
 int FindLife(const ulong id)
 {
  for(int i=0;i<ArraySize(m_life);i++) if(m_life[i].id==id) return i;
  return -1;
 }
 bool TradeDeal(const ENUM_DEAL_TYPE t) { return t==DEAL_TYPE_BUY || t==DEAL_TYPE_SELL; }
 double DealNet(const ulong t)
 {
  return HistoryDealGetDouble(t,DEAL_PROFIT)+HistoryDealGetDouble(t,DEAL_COMMISSION)
        +HistoryDealGetDouble(t,DEAL_SWAP)+HistoryDealGetDouble(t,DEAL_FEE);
 }
 bool ParseEntryComment(const string comment,int &setup,int &direction,uint &hash)
 {
  setup=0; direction=0; hash=0; string parts[];
  if(StringSplit(comment,':',parts)!=4 || parts[0]!="BVP1") return false;
  setup=(int)StringToInteger(parts[1]); direction=(int)StringToInteger(parts[2]);
  if(setup<1 || setup>3 || (direction!=1 && direction!=-1) || StringLen(parts[3])<1 || StringLen(parts[3])>10) { setup=0; direction=0; return false; }
  for(int i=0;i<StringLen(parts[3]);i++) if(StringGetCharacter(parts[3],i)<'0' || StringGetCharacter(parts[3],i)>'9') { setup=0; direction=0; return false; }
  long value=StringToInteger(parts[3]); if(value<0 || value>4294967295) { setup=0; direction=0; return false; }
  hash=(uint)value; return true;
 }
 void ParseComment(const string comment,int &setup,int &direction)
 {
  uint hash; ParseEntryComment(comment,setup,direction,hash);
 }
 bool SignalFileMatches(const string file,const string symbol,const uint hash,const int setup,const int direction)
 {
  BVPSignal signal; double risk=0;
  if(!ReadMetadata(file,signal,risk)) return false;
  return signal.valid && StringFind(signal.id,symbol+":")==0 && BVPHash(signal.id)==hash && (int)signal.setup==setup && signal.direction==direction;
 }
 bool OpeningProvenance(const ulong deal)
 {
  long magic=HistoryDealGetInteger(deal,DEAL_MAGIC);
  if(!GroupMagic(magic) || (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY)!=DEAL_ENTRY_IN) return false;
  string symbol=HistoryDealGetString(deal,DEAL_SYMBOL);
  if(G(M("Y",magic))!=(double)BVPHash(symbol)) return false;
  ulong order=(ulong)HistoryDealGetInteger(deal,DEAL_ORDER),id=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
  int setup=0,direction=0; uint hash=0;
  bool comment=ParseEntryComment(HistoryDealGetString(deal,DEAL_COMMENT),setup,direction,hash);
  if(!comment) comment=ParseEntryComment(HistoryOrderGetString(order,ORDER_COMMENT),setup,direction,hash);
  bool stored_order=GlobalVariableCheck(P("I",order)) && G(P("S",order))>=1 && G(P("S",order))<=3 && MathAbs(G(P("D",order)))==1;
  if(!comment && stored_order)
  { hash=(uint)G(P("I",order)); setup=(int)G(P("S",order)); direction=(int)G(P("D",order)); }
  if(!comment && !stored_order) return false;
  ENUM_DEAL_TYPE type=(ENUM_DEAL_TYPE)HistoryDealGetInteger(deal,DEAL_TYPE);
  if((type==DEAL_TYPE_BUY?1:-1)!=direction) return false;
  // An actual returned order ID is independent proof of our broker request.
  if(stored_order && (uint)G(P("I",order))==hash && (int)G(P("S",order))==setup && (int)G(P("D",order))==direction) return true;
  return SignalFileMatches(PositionFile(id),symbol,hash,setup,direction) || SignalFileMatches(PendingFile(magic),symbol,hash,setup,direction);
 }
 bool OrderMatchesIntent(const ulong order,const long magic,const uint hash,const datetime since)
 {
  if(HistoryOrderGetInteger(order,ORDER_MAGIC)!=magic || (datetime)HistoryOrderGetInteger(order,ORDER_TIME_SETUP)<since-2) return false;
  int setup=0,direction=0; uint parsed=0;
  if(ParseEntryComment(HistoryOrderGetString(order,ORDER_COMMENT),setup,direction,parsed) && parsed==hash)
   return SignalFileMatches(PendingFile(magic),HistoryOrderGetString(order,ORDER_SYMBOL),hash,setup,direction);
  return GlobalVariableCheck(P("I",order)) && (uint)G(P("I",order))==hash;
 }
 bool FreshMagicClear(string &reason)
 {
  if(FileIsExist(JournalFile(m_cfg.magic),FILE_COMMON)) { reason="Unregistered magic has an unresolved journal; operator reconciliation required"; return false; }
  for(int i=PositionsTotal()-1;i>=0;i--)
  { ulong t=PositionGetTicket(i); if(t>0 && PositionGetInteger(POSITION_MAGIC)==m_cfg.magic) { reason="Fresh magic collides with an existing account position"; return false; } }
  for(int i=OrdersTotal()-1;i>=0;i--)
  { ulong t=OrderGetTicket(i); if(t>0 && OrderGetInteger(ORDER_MAGIC)==m_cfg.magic) { reason="Fresh magic collides with an existing account order"; return false; } }
  if(!HistorySelect(0,TimeCurrent()+60)) { reason="Cannot verify fresh magic uniqueness: account history unavailable"; return false; }
  for(int i=0;i<HistoryDealsTotal();i++)
  { ulong t=HistoryDealGetTicket(i); if(t>0 && HistoryDealGetInteger(t,DEAL_MAGIC)==m_cfg.magic) { reason="Fresh magic collides with historical account deals; choose an unused magic"; return false; } }
  for(int i=0;i<HistoryOrdersTotal();i++)
  { ulong t=HistoryOrderGetTicket(i); if(t>0 && HistoryOrderGetInteger(t,ORDER_MAGIC)==m_cfg.magic) { reason="Fresh magic collides with historical account orders; choose an unused magic"; return false; } }
  return true;
 }
 bool LoadHistory()
 {
  m_history_ok=false;
  if(!TerminalInfoInteger(TERMINAL_CONNECTED) && !MQLInfoInteger(MQL_TESTER)) { m_status="Disconnected: history reconciliation unavailable"; return false; }
  if(!HistorySelect(0,m_broker+60)) { m_status="Account history unavailable; entries blocked"; return false; }
  ArrayResize(m_life,0);
  int total=HistoryDealsTotal();
  for(int i=0;i<total;i++)
  {
   ulong deal=HistoryDealGetTicket(i); if(deal==0) return false;
   ENUM_DEAL_TYPE type=(ENUM_DEAL_TYPE)HistoryDealGetInteger(deal,DEAL_TYPE);
   if(!TradeDeal(type)) continue;
   ulong id=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID); if(id==0) continue;
   int j=LifeIndex(id); long magic=HistoryDealGetInteger(deal,DEAL_MAGIC);
   ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY);
   datetime time=(datetime)HistoryDealGetInteger(deal,DEAL_TIME);
   double volume=HistoryDealGetDouble(deal,DEAL_VOLUME)*(type==DEAL_TYPE_BUY?1:-1);
   bool opening=entry==DEAL_ENTRY_IN || entry==DEAL_ENTRY_INOUT;
   bool ours=GroupMagic(magic) && (!opening || OpeningProvenance(deal));
   if(m_life[j].first==0 && entry!=DEAL_ENTRY_IN)
   { m_status="Position history begins with an exit/reversal; original lifecycle unavailable"; return false; }
   if(m_life[j].first==0 || time<m_life[j].first) m_life[j].first=time;
   if(time>m_life[j].last) m_life[j].last=time;
   m_life[j].symbol=HistoryDealGetString(deal,DEAL_SYMBOL);
   m_life[j].signed_volume+=volume; m_life[j].net+=DealNet(deal);
   if(!ours) m_life[j].foreign_any=true;
   if(entry==DEAL_ENTRY_IN || entry==DEAL_ENTRY_INOUT)
   {
    m_life[j].seen_in=true;
    if(!ours) m_life[j].foreign_in=true;
    if(ours)
    {
     m_life[j].group_owned=true; m_life[j].magic=magic;
     int setup,direction; ParseComment(HistoryDealGetString(deal,DEAL_COMMENT),setup,direction);
     if(setup==0)
     {
      ulong order=(ulong)HistoryDealGetInteger(deal,DEAL_ORDER);
      ParseComment(HistoryOrderGetString(order,ORDER_COMMENT),setup,direction);
      if(setup==0) { setup=(int)G(P("S",order)); direction=(int)G(P("D",order)); }
     }
     if(setup!=0) { m_life[j].setup=setup; m_life[j].direction=direction; }
    }
   }
  }
  // A position/deal without its opening lifecycle is not sufficient history.
  for(int i=0;i<ArraySize(m_life);i++)
   if(!m_life[i].seen_in) { m_status="Incomplete position lifecycle history; entries blocked"; return false; }
  for(int i=PositionsTotal()-1;i>=0;i--)
  {
   ulong ticket=PositionGetTicket(i); if(ticket==0) return false;
   ulong id=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
   if(FindLife(id)<0) { m_status="Open position missing from account history"; return false; }
  }
  m_history_ok=true; return true;
 }
 bool Netting() { return AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING; }
 bool PositionOwned(const ulong ticket)
 {
  if(!PositionSelectByTicket(ticket)) return false;
  ulong id=(ulong)PositionGetInteger(POSITION_IDENTIFIER); int i=FindLife(id);
  if(i<0 || !m_life[i].seen_in || !m_life[i].group_owned || m_life[i].foreign_in) return false;
  if(!GroupMagic(PositionGetInteger(POSITION_MAGIC))) return false;
  // External partial closes contaminate a netting lifecycle: do not modify it.
  if(Netting() && m_life[i].foreign_any) return false;
  return true;
 }
 double Floating()
 {
  double result=0;
  for(int i=PositionsTotal()-1;i>=0;i--)
  {
   ulong ticket=PositionGetTicket(i); if(ticket==0) continue;
   ulong id=(ulong)PositionGetInteger(POSITION_IDENTIFIER); int j=FindLife(id);
   // Manual exit deals remain attributable if no foreign opening/increase occurred.
   if(j>=0 && m_life[j].group_owned && !m_life[j].foreign_in)
    result+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
  }
  return result;
 }
 bool MidnightFlat()
 {
  // Rebuild account exposure at midnight, including unrelated positions.
  ulong ids[]; double volumes[]; ArrayResize(ids,0); ArrayResize(volumes,0);
  for(int i=0;i<HistoryDealsTotal();i++)
  {
   ulong d=HistoryDealGetTicket(i);
   if((datetime)HistoryDealGetInteger(d,DEAL_TIME)>=m_day_start) continue;
   ENUM_DEAL_TYPE t=(ENUM_DEAL_TYPE)HistoryDealGetInteger(d,DEAL_TYPE); if(!TradeDeal(t)) continue;
   ulong id=(ulong)HistoryDealGetInteger(d,DEAL_POSITION_ID); int j=-1;
   for(int k=0;k<ArraySize(ids);k++) if(ids[k]==id) { j=k; break; }
   if(j<0) { j=ArraySize(ids); ArrayResize(ids,j+1); ArrayResize(volumes,j+1); ids[j]=id; volumes[j]=0; }
   volumes[j]+=HistoryDealGetDouble(d,DEAL_VOLUME)*(t==DEAL_TYPE_BUY?1:-1);
  }
  for(int i=0;i<ArraySize(volumes);i++) if(MathAbs(volumes[i])>0.00000001) return false;
  return true;
 }
 bool Baseline()
 {
  string eq=m_root+".DE"+N((long)m_day),fl=D("DF");
  if(!GlobalVariableCheck(eq))
  {
   if(m_broker==m_day_start) Put(eq,AccountInfoDouble(ACCOUNT_EQUITY));
   else if(MidnightFlat())
   {
    double impacts=0;
    for(int i=0;i<HistoryDealsTotal();i++)
    {
     ulong deal=HistoryDealGetTicket(i);
     if((datetime)HistoryDealGetInteger(deal,DEAL_TIME)>=m_day_start) impacts+=DealNet(deal);
    }
    Put(eq,AccountInfoDouble(ACCOUNT_BALANCE)+AccountInfoDouble(ACCOUNT_CREDIT)-impacts);
   }
   else { m_status="NY day-start equity unknown: account carried exposure at midnight; wait for reconstructable day"; return false; }
  }
  if(!GlobalVariableCheck(fl))
  {
   if(m_broker==m_day_start) Put(fl,Floating());
   else if(MidnightFlat()) Put(fl,0);
   else { m_status="NY day-start group floating baseline unknown; new entries blocked"; return false; }
  }
  if(!BVPFinitePositive(G(eq))) { m_status="Invalid persisted day-start equity"; return false; }
  return true;
 }
 double PlannedRisk(const string symbol,const ENUM_ORDER_TYPE type,const double volume,const double entry,const double stop,const long magic)
 {
  double profit=0,tick=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
  if(!BVPFinitePositive(stop) || !BVPFinitePositive(tick) || !OrderCalcProfit(type,symbol,volume,entry,stop,profit)) return DBL_MAX;
  double adverse=stop+(type==ORDER_TYPE_BUY?-1:1)*G(M("L",magic),m_cfg.slippage_ticks)*tick;
  double slipped=0;
  if(adverse<=0 || !OrderCalcProfit(type,symbol,volume,entry,adverse,slipped)) return DBL_MAX;
  return MathMax(0,-slipped)+volume*G(M("C",magic),m_cfg.commission_per_lot_round_turn);
 }
 double RiskPositions()
 {
  double risk=0;
  for(int i=PositionsTotal()-1;i>=0;i--)
  {
   ulong ticket=PositionGetTicket(i); if(ticket==0) continue;
   ulong id=(ulong)PositionGetInteger(POSITION_IDENTIFIER); int j=FindLife(id);
   if(j<0 || !m_life[j].group_owned)
   {
    // A collision with a registered group magic is an ownership conflict,
    // never permission to ignore unknown exposure and open another chart.
    if(GroupMagic(PositionGetInteger(POSITION_MAGIC))) return DBL_MAX;
    continue;
   }
   if(m_life[j].foreign_in || (Netting() && m_life[j].foreign_any)) return DBL_MAX;
   string symbol=PositionGetString(POSITION_SYMBOL); long magic=PositionGetInteger(POSITION_MAGIC);
   ENUM_ORDER_TYPE type=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   double r=PlannedRisk(symbol,type,PositionGetDouble(POSITION_VOLUME),PositionGetDouble(POSITION_PRICE_OPEN),PositionGetDouble(POSITION_SL),magic);
   if(r==DBL_MAX) return DBL_MAX; risk+=r;
  }
  return risk;
 }
 double Reservations()
 {
  double risk=0; string prefix=m_root+".R";
  for(int i=0;i<GlobalVariablesTotal();i++)
  {
   string name=GlobalVariableName(i); if(StringFind(name,prefix)!=0) continue;
   long magic=StringToInteger(StringSubstr(name,StringLen(prefix)));
   if(GroupMagic(magic)) risk+=MathMax(0,G(name));
  }
  return risk;
 }
 bool HasOrder(const long magic)
 {
  for(int i=OrdersTotal()-1;i>=0;i--) { ulong t=OrderGetTicket(i); if(t!=0 && OrderGetInteger(ORDER_MAGIC)==magic) return true; }
  return false;
 }
 bool CancelOrder(const ulong ticket)
 {
  if(!OrderSelect(ticket) || !GroupMagic(OrderGetInteger(ORDER_MAGIC))) return false;
  long magic=OrderGetInteger(ORDER_MAGIC); string symbol=OrderGetString(ORDER_SYMBOL);
  int setup=0,direction=0; uint hash=0;
  bool proven=GlobalVariableCheck(P("I",ticket)) || GlobalVariableCheck(P("E",ticket));
  if(!proven && ParseEntryComment(OrderGetString(ORDER_COMMENT),setup,direction,hash))
   proven=SignalFileMatches(PendingFile(magic),symbol,hash,setup,direction);
  if(!proven)
  {
   ulong id=(ulong)OrderGetInteger(ORDER_POSITION_ID);
   proven=id>0 && G(P("C",id))>0 && OrderGetString(ORDER_COMMENT)=="BVPX:"+N((long)G(P("X",id)));
  }
  if(!proven) { m_status="Unproven order shares group magic; cancellation prohibited"; return false; }
  MqlTradeRequest q={}; MqlTradeResult r={}; q.action=TRADE_ACTION_REMOVE; q.order=ticket;
  bool sent=OrderSend(q,r);
  if(!sent || (r.retcode!=TRADE_RETCODE_DONE && r.retcode!=TRADE_RETCODE_INVALID_ORDER))
   Log("CANCEL_RETRY",N((long)ticket)+" retcode="+N((long)r.retcode));
  return sent && (r.retcode==TRADE_RETCODE_DONE || r.retcode==TRADE_RETCODE_INVALID_ORDER);
 }
 ENUM_ORDER_TYPE_FILLING Filling(const string symbol)
 {
  long flags=SymbolInfoInteger(symbol,SYMBOL_FILLING_MODE);
  if((flags&SYMBOL_FILLING_FOK)==SYMBOL_FILLING_FOK) return ORDER_FILLING_FOK;
  if((flags&SYMBOL_FILLING_IOC)==SYMBOL_FILLING_IOC) return ORDER_FILLING_IOC;
  // FOK is supported for instant/request execution independent of mode flags.
  long execution=SymbolInfoInteger(symbol,SYMBOL_TRADE_EXEMODE);
  if(execution==SYMBOL_TRADE_EXECUTION_INSTANT || execution==SYMBOL_TRADE_EXECUTION_REQUEST) return ORDER_FILLING_FOK;
  return (ENUM_ORDER_TYPE_FILLING)-1;
 }
 bool CloseRequestSettled(const ulong id,const long magic)
 {
  datetime since=(datetime)G(P("C",id)); if(since<=0) return true;
  string comment="BVPX:"+N((long)G(P("X",id)));
  for(int i=OrdersTotal()-1;i>=0;i--)
  {
   ulong ticket=OrderGetTicket(i);
   if(ticket>0 && OrderGetInteger(ORDER_MAGIC)==magic && (ulong)OrderGetInteger(ORDER_POSITION_ID)==id)
   { CancelOrder(ticket); if(OrderSelect(ticket)) return false; }
  }
  bool evidence=false;
  for(int i=0;i<HistoryOrdersTotal();i++)
  {
   ulong order=HistoryOrderGetTicket(i);
   if(HistoryOrderGetInteger(order,ORDER_MAGIC)!=magic || (datetime)HistoryOrderGetInteger(order,ORDER_TIME_SETUP)<since-2 || HistoryOrderGetString(order,ORDER_COMMENT)!=comment) continue;
   ENUM_ORDER_STATE state=(ENUM_ORDER_STATE)HistoryOrderGetInteger(order,ORDER_STATE);
   if(state!=ORDER_STATE_FILLED && state!=ORDER_STATE_CANCELED && state!=ORDER_STATE_REJECTED && state!=ORDER_STATE_EXPIRED) return false;
   double expected=HistoryOrderGetDouble(order,ORDER_VOLUME_INITIAL)-HistoryOrderGetDouble(order,ORDER_VOLUME_CURRENT),observed=0;
   for(int j=0;j<HistoryDealsTotal();j++)
   {
    ulong deal=HistoryDealGetTicket(j);
    if((ulong)HistoryDealGetInteger(deal,DEAL_ORDER)==order && TradeDeal((ENUM_DEAL_TYPE)HistoryDealGetInteger(deal,DEAL_TYPE))) observed+=HistoryDealGetDouble(deal,DEAL_VOLUME);
   }
   if(observed+0.00000001<expected) return false;
   evidence=true;
  }
  if(evidence) { Put(P("C",id),0); return true; }
  m_status="Indeterminate close request; awaiting broker history before any further close";
  return false;
 }
 bool Close(const ulong ticket,const string why)
 {
  if(!PositionOwned(ticket)) return false;
  string symbol=PositionGetString(POSITION_SYMBOL); ulong id=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
  long magic=PositionGetInteger(POSITION_MAGIC);
  // A required exit survives a rejected request, a NY day rollover, and loss
  // of clock conversion. Clearing the in-flight request never clears this.
  if(G(P("Z",id))<=0) { Put(P("Z",id),1); GlobalVariablesFlush(); }
  if(!CloseRequestSettled(id,magic)) return false;
  // Cancel residual opening orders before closing the filled exposure.
  for(int i=OrdersTotal()-1;i>=0;i--)
  {
   ulong order=OrderGetTicket(i);
   if(order>0 && OrderGetString(ORDER_SYMBOL)==symbol && GroupMagic(OrderGetInteger(ORDER_MAGIC)))
   { CancelOrder(order); if(OrderSelect(order)) return false; }
  }
  if(!PositionOwned(ticket)) return false;
  MqlTick tick;
  if(!SymbolInfoTick(symbol,tick)) return false;
  MqlTradeRequest q={}; MqlTradeResult r={};
  q.action=TRADE_ACTION_DEAL; q.position=ticket; q.symbol=symbol;
  q.magic=(ulong)PositionGetInteger(POSITION_MAGIC); q.volume=PositionGetDouble(POSITION_VOLUME);
  q.type=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?ORDER_TYPE_SELL:ORDER_TYPE_BUY;
  q.price=q.type==ORDER_TYPE_BUY?tick.ask:tick.bid; q.deviation=(ulong)m_cfg.deviation_points;
  uint close_hash=BVPHash(N((long)id)+"|"+N((long)GetMicrosecondCount())+"|"+N((long)TimeLocal()));
  q.type_filling=Filling(symbol); q.comment="BVPX:"+N((long)close_hash);
  if((int)q.type_filling<0) { Log("CLOSE_RETRY","No supported FOK/IOC filling mode for "+symbol); return false; }
  Put(P("C",id),(double)m_broker); Put(P("X",id),(double)close_hash); GlobalVariablesFlush();
  bool ok=OrderSend(q,r);
  if(r.order>0) Put(P("E",r.order),(double)close_hash);
  bool accepted=r.retcode==TRADE_RETCODE_DONE || r.retcode==TRADE_RETCODE_DONE_PARTIAL || r.retcode==TRADE_RETCODE_PLACED;
  bool unknown=r.retcode==TRADE_RETCODE_TIMEOUT || r.retcode==TRADE_RETCODE_CONNECTION || r.retcode==0 || r.retcode==TRADE_RETCODE_ERROR;
  if(!accepted && !unknown) Put(P("C",id),0);
  GlobalVariablesFlush();
  Log("CLOSE",why+" ticket="+N((long)ticket)+" retcode="+N((long)r.retcode)+" volume="+DoubleToString(r.volume,8));
  return ok && r.retcode==TRADE_RETCODE_DONE;
 }
 void CloseGroup(const string why)
 {
  for(int i=OrdersTotal()-1;i>=0;i--) { ulong t=OrderGetTicket(i); if(t!=0 && GroupMagic(OrderGetInteger(ORDER_MAGIC))) CancelOrder(t); }
  for(int i=PositionsTotal()-1;i>=0;i--) { ulong t=PositionGetTicket(i); if(t!=0 && PositionOwned(t)) Close(t,why); }
 }
 void ReconcileReservations()
 {
  string prefix=m_root+".R";
  for(int i=GlobalVariablesTotal()-1;i>=0;i--)
  {
   string name=GlobalVariableName(i); if(StringFind(name,prefix)!=0 || G(name)<=0) continue;
   long magic=StringToInteger(StringSubstr(name,StringLen(prefix))); if(!GroupMagic(magic)) continue;
   // Cancel any residual market-order remainder before releasing reserved risk.
   if(HasOrder(magic))
   {
    for(int j=OrdersTotal()-1;j>=0;j--) { ulong t=OrderGetTicket(j); if(t!=0 && OrderGetInteger(ORDER_MAGIC)==magic) CancelOrder(t); }
    if(HasOrder(magic)) continue;
   }
   datetime since=(datetime)G(M("T",magic)); uint hash=(uint)G(M("I",magic));
   bool evidence=false;
   for(int j=0;j<HistoryOrdersTotal();j++)
   {
    ulong order=HistoryOrderGetTicket(j);
    if(!OrderMatchesIntent(order,magic,hash,since)) continue;
    ENUM_ORDER_STATE state=(ENUM_ORDER_STATE)HistoryOrderGetInteger(order,ORDER_STATE);
    if(state!=ORDER_STATE_FILLED && state!=ORDER_STATE_CANCELED && state!=ORDER_STATE_REJECTED && state!=ORDER_STATE_EXPIRED) continue;
    evidence=true;
    ulong id=(ulong)HistoryOrderGetInteger(order,ORDER_POSITION_ID);
    if(id>0)
    {
     if(!GlobalVariableCheck(P("L",id))) Put(P("L",id),G(M("K",magic)));
     if(!GlobalVariableCheck(P("B",id))) Put(P("B",id),G(name));
     if(!GlobalVariableCheck(P("V",id))) Put(P("V",id),G(M("V",magic)));
     if(!FileIsExist(PositionFile(id),FILE_COMMON)) FileCopy(PendingFile(magic),FILE_COMMON,PositionFile(id),FILE_COMMON);
    }
   }
   // Terminal order state may arrive before its partial-fill deals. Do not
   // release a reservation until every executed lot has appeared in history.
   if(evidence)
   {
    bool awaiting=false;
    for(int j=0;j<HistoryOrdersTotal();j++)
    {
     ulong order=HistoryOrderGetTicket(j);
     if(!OrderMatchesIntent(order,magic,hash,since)) continue;
     double expected=HistoryOrderGetDouble(order,ORDER_VOLUME_INITIAL)-HistoryOrderGetDouble(order,ORDER_VOLUME_CURRENT);
     double observed=0;
     for(int k=0;k<HistoryDealsTotal();k++)
     {
      ulong deal=HistoryDealGetTicket(k);
      if((ulong)HistoryDealGetInteger(deal,DEAL_ORDER)==order && TradeDeal((ENUM_DEAL_TYPE)HistoryDealGetInteger(deal,DEAL_TYPE))) observed+=HistoryDealGetDouble(deal,DEAL_VOLUME);
     }
     if(observed+0.00000001<expected) awaiting=true;
     if((ENUM_ORDER_STATE)HistoryOrderGetInteger(order,ORDER_STATE)==ORDER_STATE_FILLED && FindLife((ulong)HistoryOrderGetInteger(order,ORDER_POSITION_ID))<0) awaiting=true;
    }
    if(!awaiting) { Put(name,0); Put(M("W",magic),0); FileDelete(JournalFile(magic),FILE_COMMON); }
   }
  }
 }
 void DailyState()
 {
  double realized=0;
  for(int i=0;i<HistoryDealsTotal();i++)
  {
   ulong deal=HistoryDealGetTicket(i); if((datetime)HistoryDealGetInteger(deal,DEAL_TIME)<m_day_start) continue;
   ulong id=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID); int j=FindLife(id);
   if(j>=0 && m_life[j].group_owned && !m_life[j].foreign_in) realized+=DealNet(deal);
  }
  m_daily=realized+Floating()-G(D("DF"));
  // Closed lifecycles, not partial exit deals, define consecutive losses.
  int losses=0; datetime cursor=0; ulong cursorid=0;
  for(int pass=0;pass<ArraySize(m_life);pass++)
  {
   int next=-1;
   for(int j=0;j<ArraySize(m_life);j++)
   {
    if(!m_life[j].group_owned || m_life[j].foreign_in || MathAbs(m_life[j].signed_volume)>0.00000001 || m_life[j].last<m_day_start) continue;
    if(m_life[j].last<cursor || (m_life[j].last==cursor && m_life[j].id<=cursorid)) continue;
    if(next<0 || m_life[j].last<m_life[next].last || (m_life[j].last==m_life[next].last && m_life[j].id<m_life[next].id)) next=j;
   }
   if(next<0) break;
   cursor=m_life[next].last; cursorid=m_life[next].id;
   losses=m_life[next].net< -0.00000001?losses+1:0;
   if(losses>=m_cfg.max_losses) Put(D("LOSS"),1);
  }
  double eq=G(m_root+".DE"+N((long)m_day));
  if(eq>0 && m_daily<=-eq*m_cfg.daily_loss_percent/100.0) Put(D("LOSS"),1);
  m_blocked=G(D("LOSS"))>0 || G(m_group+".FATAL")>0;
 }
 void Protect()
 {
  for(int i=PositionsTotal()-1;i>=0;i--)
  {
   ulong ticket=PositionGetTicket(i); if(ticket==0 || !PositionOwned(ticket)) continue;
   ulong id=(ulong)PositionGetInteger(POSITION_IDENTIFIER); string symbol=PositionGetString(POSITION_SYMBOL);
   double stop=PositionGetDouble(POSITION_SL),tp=PositionGetDouble(POSITION_TP);
   if(stop<=0 || tp<=0)
   {
    Put(m_group+".FATAL",1); m_status="Protection absent after fill; emergency close, persistent group error";
    Close(ticket,m_status); continue;
   }
   if(G(P("Z",id))>0) { Close(ticket,"Previously required exit; persistent retry"); continue; }
   double original=G(P("L",id)),budget=G(P("B",id)),submitted=G(P("V",id));
   long position_magic=PositionGetInteger(POSITION_MAGIC);
   bool active_reservation=G(M("R",position_magic))>0;
   if((original<=0 || budget<=0 || submitted<=0) && active_reservation)
   {
    // A deal/position can precede its terminal historical order. Recover
    // directly from a matching write-ahead intent rather than treating normal
    // transaction ordering as corrupt protection metadata.
    uint pending_hash=(uint)G(M("I",position_magic));
    datetime pending_since=(datetime)G(M("T",position_magic));
    bool matched=false;
    for(int j=0;j<HistoryDealsTotal();j++)
    {
     ulong deal=HistoryDealGetTicket(j);
     if((ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID)!=id || HistoryDealGetInteger(deal,DEAL_MAGIC)!=position_magic || (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY)!=DEAL_ENTRY_IN || (datetime)HistoryDealGetInteger(deal,DEAL_TIME)<pending_since-2) continue;
     string comment=HistoryDealGetString(deal,DEAL_COMMENT); string parts[];
     if(StringSplit(comment,':',parts)==4 && parts[0]=="BVP1" && (uint)StringToInteger(parts[3])==pending_hash) { matched=true; break; }
    }
    if(matched)
    {
     original=G(M("K",position_magic)); budget=G(M("R",position_magic)); submitted=G(M("V",position_magic));
     if(original>0 && budget>0 && submitted>0)
     {
      Put(P("L",id),original); Put(P("B",id),budget); Put(P("V",id),submitted);
      if(!FileIsExist(PositionFile(id),FILE_COMMON)) FileCopy(PendingFile(position_magic),FILE_COMMON,PositionFile(id),FILE_COMMON);
     }
    }
   }
   if(original<=0 || budget<=0 || submitted<=0)
   {
    // Recover original order protection after a restart even when no reservation remains.
    for(int j=0;j<HistoryOrdersTotal();j++)
    {
     ulong order=HistoryOrderGetTicket(j);
     if((ulong)HistoryOrderGetInteger(order,ORDER_POSITION_ID)!=id || !GroupMagic(HistoryOrderGetInteger(order,ORDER_MAGIC))) continue;
     double candidate=HistoryOrderGetDouble(order,ORDER_SL);
     if(candidate>0 && original<=0) original=candidate;
    }
    if(original>0) Put(P("L",id),original);
   }
   if(original<=0 || budget<=0 || submitted<=0)
   {
    if(active_reservation)
    {
     // The actual SL/TP were verified above. Keep the full reservation while
     // awaiting broker history; do not create a permanent fatal latch merely
     // because historical order/deal notifications arrived out of sequence.
     m_status="Awaiting original fill metadata; full reservation remains held"; continue;
    }
    Put(m_group+".FATAL",1); Close(ticket,"Original risk metadata unavailable; fail-closed recovery"); continue;
   }
   // Position properties can change during history scans; reselect before use.
   if(!PositionSelectByTicket(ticket)) continue;
   ENUM_ORDER_TYPE type=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   bool buy=type==ORDER_TYPE_BUY; double entry=PositionGetDouble(POSITION_PRICE_OPEN),vol=PositionGetDouble(POSITION_VOLUME);
   if((buy && stop<original-0.00000001) || (!buy && stop>original+0.00000001))
   { Put(m_group+".FATAL",1); Close(ticket,"Protective stop widened externally; close safely"); continue; }
   double risk=PlannedRisk(symbol,type,vol,entry,stop,PositionGetInteger(POSITION_MAGIC));
   long magic=PositionGetInteger(POSITION_MAGIC);
   double allowed=budget*(vol/submitted)*(1+G(M("F",magic),m_cfg.fill_risk_tolerance_percent)/100.0);
   if(risk>allowed || (buy?entry<=original:entry>=original))
   { Close(ticket,"Actual fill exceeds planned risk tolerance or crosses original stop"); continue; }
   double tick=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
   double target_r=G(M("J",magic),m_cfg.target_r);
   double target=buy?BVPTickCeil(entry+target_r*(entry-original),tick):BVPTickFloor(entry-target_r*(original-entry),tick);
   if(MathAbs(tp-target)<tick*0.5) continue;
   MqlTick quote; if(!SymbolInfoTick(symbol,quote)) continue;
   double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
   double min_dist=(double)MathMax(SymbolInfoInteger(symbol,SYMBOL_TRADE_STOPS_LEVEL),SymbolInfoInteger(symbol,SYMBOL_TRADE_FREEZE_LEVEL))*point;
   if((buy && (target-quote.bid<min_dist || quote.bid-stop<min_dist)) || (!buy && (quote.ask-target<min_dist || stop-quote.ask<min_dist))) continue;
   MqlTradeRequest q={}; MqlTradeResult r={}; q.action=TRADE_ACTION_SLTP; q.position=ticket; q.symbol=symbol;
   q.magic=(ulong)PositionGetInteger(POSITION_MAGIC); q.sl=stop; q.tp=target;
   if(OrderSend(q,r) && r.retcode==TRADE_RETCODE_DONE) Log("TARGET_FILL_R","ticket="+N((long)ticket)+" TP="+DoubleToString(target,(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS)));
  }
 }
 bool SessionOpen(const string symbol,const datetime now)
 {
  MqlDateTime d; TimeToStruct(now,d); int seconds=d.hour*3600+d.min*60+d.sec;
  datetime from,to; bool has=false;
  for(uint i=0;i<32;i++)
  {
   if(!SymbolInfoSessionTrade(symbol,(ENUM_DAY_OF_WEEK)d.day_of_week,i,from,to)) break;
   has=true; long a=(long)from%86400,b=(long)to%86400;
   if(a==b || (a<b && seconds>=a && seconds<b) || (a>b && seconds>=a)) return true;
  }
  // Some brokers publish overnight periods against their starting weekday.
  for(uint i=0;i<32;i++)
  {
   if(!SymbolInfoSessionTrade(symbol,(ENUM_DAY_OF_WEEK)((d.day_of_week+6)%7),i,from,to)) break;
   long a=(long)from%86400,b=(long)to%86400;
   if(a>b && seconds<b) return true;
  }
  return false; // Unpublished session information is not an implied permission.
 }
 bool EntryCounts(const BVPSignal &s,string &reason)
 {
  ulong orders[]; int symbol_count=0,setup_count=0;
  for(int i=0;i<HistoryDealsTotal();i++)
  {
   ulong deal=HistoryDealGetTicket(i);
   if((datetime)HistoryDealGetInteger(deal,DEAL_TIME)<m_day_start || HistoryDealGetString(deal,DEAL_SYMBOL)!=m_symbol || !GroupMagic(HistoryDealGetInteger(deal,DEAL_MAGIC))) continue;
   ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY);
   if(entry!=DEAL_ENTRY_IN && entry!=DEAL_ENTRY_INOUT) continue;
   ulong order=(ulong)HistoryDealGetInteger(deal,DEAL_ORDER); bool seen=false;
   for(int j=0;j<ArraySize(orders);j++) if(orders[j]==order) seen=true;
   if(seen) continue; int n=ArraySize(orders); ArrayResize(orders,n+1); orders[n]=order; symbol_count++;
   int setup,direction; ParseComment(HistoryDealGetString(deal,DEAL_COMMENT),setup,direction);
   if(setup==0) ParseComment(HistoryOrderGetString(order,ORDER_COMMENT),setup,direction);
   if(setup==0) { setup=(int)G(P("S",order)); direction=(int)G(P("D",order)); }
   if(setup==0 || (setup==(int)s.setup && direction==s.direction)) setup_count++;
  }
  if(symbol_count>=m_cfg.max_symbol_entries) { reason="Maximum filled symbol entries for NY day"; return false; }
  if(setup_count>=m_cfg.max_setup_direction_entries) { reason="Maximum filled setup/direction entries for NY day (unknown metadata counts conservatively)"; return false; }
  return true;
 }
 bool EntryFilters(const BVPSignal &s,const MqlTick &tick,string &reason)
 {
  if(!s.valid || s.id=="" || (s.direction!=1 && s.direction!=-1) || s.setup<1 || s.setup>3) { reason="Invalid signal"; return false; }
  if(m_broker>=s.expires_broker || m_broker<=s.bar_time) { reason="Signal expired or not subsequent tick"; return false; }
  if(!BVPFinitePositive(tick.bid) || !BVPFinitePositive(tick.ask) || tick.ask<tick.bid || m_broker-tick.time>m_cfg.quote_max_age_seconds || tick.time>m_broker+2) { reason="Invalid or stale quote"; return false; }
  if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED) || !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) || !AccountInfoInteger(ACCOUNT_TRADE_EXPERT)) { reason="Terminal/account expert trading permission unavailable"; return false; }
  if(!m_cfg.allow_live && AccountInfoInteger(ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_REAL && !MQLInfoInteger(MQL_TESTER)) { reason="AllowLiveTrading=false"; return false; }
  long mode=SymbolInfoInteger(m_symbol,SYMBOL_TRADE_MODE),orders=SymbolInfoInteger(m_symbol,SYMBOL_ORDER_MODE);
  if(mode==SYMBOL_TRADE_MODE_DISABLED || mode==SYMBOL_TRADE_MODE_CLOSEONLY || (s.direction>0 && mode==SYMBOL_TRADE_MODE_SHORTONLY) || (s.direction<0 && mode==SYMBOL_TRADE_MODE_LONGONLY)) { reason="Symbol trade direction not permitted"; return false; }
  if((orders&SYMBOL_ORDER_MARKET)==0 || (orders&SYMBOL_ORDER_SL)==0 || (orders&SYMBOL_ORDER_TP)==0) { reason="Symbol does not support market orders with initial SL and TP"; return false; }
  if(!SessionOpen(m_symbol,m_broker)) { reason="Symbol trade session closed or unavailable"; return false; }
  for(int i=PositionsTotal()-1;i>=0;i--)
  {
   ulong ticket=PositionGetTicket(i); if(ticket!=0 && PositionGetString(POSITION_SYMBOL)==m_symbol)
   { reason=PositionOwned(ticket)?"One position per symbol":"Existing symbol position is not unambiguously EA-owned"; return false; }
  }
  for(int i=OrdersTotal()-1;i>=0;i--) { ulong ticket=OrderGetTicket(i); if(ticket!=0 && OrderGetString(ORDER_SYMBOL)==m_symbol) { reason="Existing symbol order blocks entry"; return false; } }
  if(!BVPFinitePositive(s.atr)) { reason="Invalid completed-bar ATR"; return false; }
  double entry=s.direction>0?tick.ask:tick.bid,dist=s.direction>0?entry-s.stop:s.stop-entry;
  if(dist<=0) { reason="Technical stop is on wrong side of entry"; return false; }
  double spread=tick.ask-tick.bid;
  if(spread>m_cfg.spread_atr_fraction*s.atr) { reason="Spread exceeds ATR threshold"; return false; }
  if(spread>m_cfg.spread_stop_fraction*dist) { reason="Spread exceeds stop-distance threshold"; return false; }
  if(MathAbs(entry-s.close)>m_cfg.max_entry_drift_atr*s.atr) { reason="Entry drift exceeds ATR threshold"; return false; }
  if(!EntryCounts(s,reason)) return false;
  return true;
 }
 bool SubmitLocked(const BVPSignal &s,const MqlTick &tick,string &reason)
 {
  if(!OwnLease()) { reason=m_status; return false; }
  string seen=D("S")+"."+N((long)BVPHash(s.id));
  if(GlobalVariableCheck(seen)) { reason="Signal identifier already processed"; return false; }
  if(!LoadHistory() || !Baseline()) { reason=m_status; return false; }
  ReconcileReservations(); DailyState();
  if(m_blocked) { reason="Persistent daily-loss or execution-error group latch"; return false; }
  if(G(M("R",m_cfg.magic))>0) { reason="Prior request remains unresolved; reservation quarantined"; return false; }
  if(!EntryFilters(s,tick,reason)) return false;
  double equity=AccountInfoDouble(ACCOUNT_EQUITY),budget=equity*m_cfg.risk_percent/100.0;
  if(!BVPFinitePositive(equity) || !BVPFinitePositive(budget)) { reason="Invalid equity/risk budget"; return false; }
  double tick_size=SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_SIZE),point=SymbolInfoDouble(m_symbol,SYMBOL_POINT);
  double vmin=SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_MIN),vmax=SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_MAX),step=SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_STEP);
  int digits=(int)SymbolInfoInteger(m_symbol,SYMBOL_DIGITS);
  if(!BVPFinitePositive(tick_size) || !BVPFinitePositive(point) || !BVPFinitePositive(vmin) || !BVPFinitePositive(vmax) || !BVPFinitePositive(step)) { reason="Invalid dynamic symbol tick/volume specifications"; return false; }
  // Query contract mode even though OrderCalcProfit/OrderCalcMargin perform its calculation.
  long calc_mode=SymbolInfoInteger(m_symbol,SYMBOL_TRADE_CALC_MODE);
  if(calc_mode<0) { reason="Invalid contract calculation mode"; return false; }
  bool buy=s.direction>0; ENUM_ORDER_TYPE type=buy?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
  double entry=buy?tick.ask:tick.bid;
  // Round technical stops away from exposure; never tighten a stop to fit volume.
  double stop=NormalizeDouble(buy?BVPTickFloor(s.stop,tick_size):BVPTickCeil(s.stop,tick_size),digits);
  double target=NormalizeDouble(buy?BVPTickCeil(entry+m_cfg.target_r*(entry-stop),tick_size):BVPTickFloor(entry-m_cfg.target_r*(stop-entry),tick_size),digits);
  double min_dist=(double)MathMax(SymbolInfoInteger(m_symbol,SYMBOL_TRADE_STOPS_LEVEL),SymbolInfoInteger(m_symbol,SYMBOL_TRADE_FREEZE_LEVEL))*point;
  if((buy && (tick.bid-stop<min_dist || target-tick.bid<min_dist)) || (!buy && (stop-tick.ask<min_dist || tick.ask-target<min_dist))) { reason="Initial SL/TP violates broker stop/freeze distance"; return false; }
  if(s.setup==VALUE_REENTRY && m_cfg.reentry_space_filter && ((buy && (entry>=s.poc || target>s.poc)) || (!buy && (entry<=s.poc || target<s.poc)))) { reason="Value re-entry POC space filter at executable price"; return false; }
  double unit=PlannedRisk(m_symbol,type,vmin,entry,stop,m_cfg.magic)/vmin;
  if(!BVPFinitePositive(unit) || unit==DBL_MAX) { reason="OrderCalcProfit cannot establish account-currency risk"; return false; }
  double volume=BVPVolumeFloor(MathMin(vmax,budget/unit),step);
  if(volume<vmin-1e-10 || volume<=0) { reason="Minimum lot exceeds risk budget"; return false; }
  double risk=PlannedRisk(m_symbol,type,volume,entry,stop,m_cfg.magic);
  // Floating point guards can only reduce size.
  if(risk>budget+0.0000001) { volume=NormalizeDouble(volume-step,8); risk=PlannedRisk(m_symbol,type,volume,entry,stop,m_cfg.magic); }
  if(volume<vmin-1e-10 || risk>budget+0.0000001) { reason="Floored permitted lot cannot fit risk budget"; return false; }
  double limit=SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_LIMIT);
  if(limit>0 && volume>limit+1e-10) { reason="Symbol directional volume limit"; return false; }
  m_open=RiskPositions(); m_proposed=risk;
  if(m_open==DBL_MAX || m_open+Reservations()+risk>equity*m_cfg.aggregate_percent/100.0+0.0000001) { reason="Group aggregate open plus reserved risk cap"; return false; }
  double margin=0;
  if(!OrderCalcMargin(type,m_symbol,volume,entry,margin) || margin>AccountInfoDouble(ACCOUNT_MARGIN_FREE)) { reason="OrderCalcMargin/free margin check failed"; return false; }
  MqlTradeRequest q={}; MqlTradeCheckResult check={}; MqlTradeResult result={};
  q.action=TRADE_ACTION_DEAL; q.symbol=m_symbol; q.magic=(ulong)m_cfg.magic; q.volume=volume; q.type=type;
  q.price=entry; q.sl=stop; q.tp=target; q.deviation=(ulong)m_cfg.deviation_points; q.type_filling=Filling(m_symbol);
  if((int)q.type_filling<0) { reason="Market/exchange symbol lacks supported FOK/IOC filling mode"; return false; }
  uint hash=BVPHash(s.id); q.comment="BVP1:"+N((long)s.setup)+":"+N(s.direction)+":"+N((long)hash);
  if(!OrderCheck(q,check) || (check.retcode!=0 && check.retcode!=TRADE_RETCODE_DONE)) { reason="OrderCheck failed "+N((long)check.retcode)+" "+check.comment; return false; }
  if(!SavePending(s,risk)) { reason="Cannot persist full signal/risk metadata; order blocked"; return false; }
  if(!Journal(s,risk,stop,volume)) { reason="Cannot persist write-ahead reservation journal; order blocked"; return false; }
  // The durable signal marker precedes OrderSend, including failed requests.
  Put(seen,1);
  Put(M("R",m_cfg.magic),risk); Put(M("T",m_cfg.magic),(double)m_broker);
  Put(M("I",m_cfg.magic),(double)hash); Put(M("K",m_cfg.magic),stop); Put(M("V",m_cfg.magic),volume);
  Put(M("W",m_cfg.magic),1); GlobalVariablesFlush();
  bool sent=OrderSend(q,result);
  if(result.order>0)
  {
   Put(P("S",result.order),(double)s.setup); Put(P("D",result.order),(double)s.direction);
   Put(P("I",result.order),(double)hash);
   // Store by returned position identifier if already visible; reservations also rebuild it.
  }
  bool accepted=result.retcode==TRADE_RETCODE_DONE || result.retcode==TRADE_RETCODE_DONE_PARTIAL || result.retcode==TRADE_RETCODE_PLACED;
  bool unknown=result.retcode==TRADE_RETCODE_TIMEOUT || result.retcode==TRADE_RETCODE_CONNECTION || result.retcode==0 || result.retcode==TRADE_RETCODE_ERROR;
  if(!accepted && !unknown) { Put(M("R",m_cfg.magic),0); Put(M("W",m_cfg.magic),0); FileDelete(JournalFile(m_cfg.magic),FILE_COMMON); }
  else Put(M("W",m_cfg.magic),accepted?2:3);
  GlobalVariablesFlush();
  reason="signal="+s.id+" setup="+BVPSetupName(s.setup)+" direction="+N(s.direction)+" retcode="+N((long)result.retcode)+
         " order="+N((long)result.order)+" deal="+N((long)result.deal)+" lots="+DoubleToString(volume,8)+" fill_lots="+DoubleToString(result.volume,8)+
         " requested="+DoubleToString(entry,digits)+" fill="+DoubleToString(result.price,digits)+" SL="+DoubleToString(stop,digits)+" TP="+DoubleToString(target,digits)+
         " spread="+DoubleToString(tick.ask-tick.bid,digits)+" risk="+DoubleToString(risk,2)+" "+result.comment;
  Log(accepted?"ENTRY_ACCEPTED":(unknown?"ENTRY_UNKNOWN":"ENTRY_REJECTED"),reason);
  // Even a synchronous fill is reconciled against actual account history.
  if(LoadHistory()) { ReconcileReservations(); Protect(); }
  return sent && accepted;
 }

public:
 CBVPExecution() { m_ready=false; m_mutex=0; m_token=0; m_daily=0; m_open=0; m_proposed=0; m_day=0; m_day_start=0; m_broker=0; m_utc=0; m_blocked=true; m_history_ok=false; }
 bool Init(const string symbol,const BVPRiskConfig &cfg,string &reason)
 {
  m_cfg=cfg; m_symbol=symbol;
  if(cfg.magic<=0 || cfg.group_id<=0 || cfg.magic>9007199254740991 || cfg.group_id>9007199254740991 || cfg.risk_percent<=0 || cfg.aggregate_percent<=0 || cfg.daily_loss_percent<=0 || cfg.risk_percent>cfg.aggregate_percent || cfg.max_losses<1 || cfg.max_symbol_entries<1 || cfg.max_setup_direction_entries<1 || cfg.target_r<=0 || cfg.commission_per_lot_round_turn<0 || cfg.slippage_ticks<0 || cfg.fill_risk_tolerance_percent<0 || cfg.quote_max_age_seconds<1 || cfg.deviation_points<0 || cfg.spread_atr_fraction<=0 || cfg.spread_stop_fraction<=0 || cfg.max_entry_drift_atr<=0)
  { reason="Invalid risk configuration or nonpositive/out-of-range magic/group"; return false; }
  string account=N(AccountInfoInteger(ACCOUNT_LOGIN))+"|"+AccountInfoString(ACCOUNT_SERVER);
  // Common Files survive tester passes. Isolate each tester run so reused
  // simulated position IDs cannot read metadata from an earlier backtest.
  if(MQLInfoInteger(MQL_TESTER)) account+="|TEST|"+N((long)TimeLocal())+"|"+N((long)GetMicrosecondCount());
  m_root="BVP1."+N((long)BVPHash(account)); m_group=m_root+".G"+N(cfg.group_id);
  m_symbol_key=m_root+".S"+N((long)BVPHash(symbol));
  m_token=(double)BVPHash(N(ChartID())+"|"+N((long)GetMicrosecondCount())+"|"+N((long)TimeLocal()));
  if(m_token==0) m_token=1;
  if(!Lock()) { reason="Account registry mutex busy; retry attachment"; return false; }
  bool ok=RestoreRegistry(); if(!ok) reason="Persistent magic registry invalid/unreadable; inspect common-files registry";
  if(ok && !GlobalVariableCheck(M("M",cfg.magic))) ok=FreshMagicClear(reason);
  if(ok && G(m_symbol_key)!=0 && G(m_symbol_key+"H")>(double)TimeLocal()) { reason="Another active instance already owns this account symbol"; ok=false; }
  if(ok && GlobalVariableCheck(M("M",cfg.magic)) && (G(M("M",cfg.magic))!=(double)cfg.group_id || G(M("Y",cfg.magic))!=(double)BVPHash(symbol))) { reason="Magic already registered to another group or symbol; use a unique magic"; ok=false; }
  string policy=DoubleToString(cfg.aggregate_percent,8)+"|"+DoubleToString(cfg.daily_loss_percent,8)+"|"+N(cfg.max_losses)+"|"+N((long)cfg.close_on_daily_loss);
  if(ok && GlobalVariableCheck(m_group+".POL") && G(m_group+".POL")!=(double)BVPHash(policy)) { reason="Group instances must use identical aggregate/daily-loss/loss-count/close policy"; ok=false; }
  if(ok && !SaveRegistry(BVPHash(policy))) { reason="Cannot persist account magic registry"; ok=false; }
  if(ok)
  {
   Put(M("M",cfg.magic),(double)cfg.group_id); Put(M("Y",cfg.magic),(double)BVPHash(symbol));
   Put(M("C",cfg.magic),cfg.commission_per_lot_round_turn); Put(M("L",cfg.magic),cfg.slippage_ticks);
   Put(M("J",cfg.magic),cfg.target_r); Put(M("F",cfg.magic),cfg.fill_risk_tolerance_percent);
   Put(m_group+".POL",(double)BVPHash(policy)); Put(m_symbol_key,m_token); Put(m_symbol_key+"H",(double)TimeLocal()+120);
   if(FileIsExist(m_group+"_fatal.txt",FILE_COMMON)) Put(m_group+".FATAL",1);
   m_ready=true; reason="Execution initialized; awaiting NY-day reconciliation"; m_status=reason; GlobalVariablesFlush();
  }
  Unlock(); return ok;
 }
 void Shutdown()
 {
  if(m_ready && Lock())
  {
   if(G(m_symbol_key)==m_token) { Put(m_symbol_key,0); Put(m_symbol_key+"H",0); }
   GlobalVariablesFlush(); Unlock();
  }
  m_ready=false;
 }
 void Supervise(datetime broker_now,datetime utc_now,datetime nyday,datetime day_start_broker,bool close_at_window)
 {
  m_broker=broker_now; m_utc=utc_now; m_day=nyday; m_day_start=day_start_broker;
  if(!m_ready) return;
  if(!Lock()) { m_status="Account execution mutex busy; supervision retries"; return; }
  if(!OwnLease()) { m_blocked=true; Unlock(); return; }
  if(!LoadHistory()) { m_blocked=true; Unlock(); return; }
  ReconcileReservations();
  if(utc_now<=0 || nyday<=0 || day_start_broker<=0 || day_start_broker>broker_now)
  {
   Protect(); m_open=RiskPositions();
   if(G(m_group+".FATAL")>0) CloseGroup("Persistent execution protection error");
   m_blocked=true; m_status="Time conversion invalid: entries blocked; protective supervision remains active";
   GlobalVariablesFlush(); Unlock(); return;
  }
  bool baseline=Baseline(); string baseline_status=m_status;
  DailyState(); Protect();
  m_open=RiskPositions();
  if(G(D("LOSS"))>0 && m_cfg.close_on_daily_loss) CloseGroup("Latched group daily-loss/consecutive-loss breach");
  if(G(m_group+".FATAL")>0) CloseGroup("Persistent execution protection error");
  if(close_at_window)
  {
   for(int i=PositionsTotal()-1;i>=0;i--) { ulong t=PositionGetTicket(i); if(t!=0 && PositionGetString(POSITION_SYMBOL)==m_symbol && PositionOwned(t)) Close(t,"NY entry window ended"); }
  }
  m_blocked=m_blocked || !baseline || m_open==DBL_MAX || G(M("R",m_cfg.magic))>0;
  if(G(m_group+".FATAL")>0) m_status="Persistent protection error; group closure retries; investigate before reset";
  else if(G(D("LOSS"))>0) m_status="Group daily-loss/consecutive-loss latch until next NY day";
  else if(!baseline) m_status=baseline_status;
  else if(m_open==DBL_MAX) m_status="Group ownership or protective-risk reconciliation conflict";
  else if(G(M("R",m_cfg.magic))>0) m_status="Pending/indeterminate request; reserved risk remains quarantined";
  else m_status="Execution risk checks ready";
  GlobalVariablesFlush(); Unlock();
 }
 bool Submit(const BVPSignal &signal,const MqlTick &tick,datetime utc_now,datetime nyday,datetime day_start_broker,string &reason)
 {
  m_broker=TimeCurrent(); m_utc=utc_now; m_day=nyday; m_day_start=day_start_broker;
  if(!m_ready) { reason="Execution not initialized"; return false; }
  if(utc_now<=0 || nyday<=0 || day_start_broker<=0 || day_start_broker>m_broker) { reason="Invalid NY-day time context"; return false; }
  if(!Lock()) { reason="Atomic account risk reservation busy; signal skipped"; return false; }
  bool result=SubmitLocked(signal,tick,reason); m_status=reason;
  if(!result)
  {
   string key=signal.id+"|"+reason;
   if(key!=m_last_skip) { Log("SKIP","signal="+signal.id+" "+reason); m_last_skip=key; }
  }
  else m_last_skip="";
  Unlock(); return result;
 }
 void Transaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
 {
  if(!m_ready) return;
  if(trans.type==TRADE_TRANSACTION_DEAL_ADD && trans.deal>0)
  {
   // Full lifecycle selection occurs on the next timer/tick; this log does not
   // replace reconciliation, and never assumes the incoming deal is ours.
   if(HistoryDealSelect(trans.deal))
   {
    ulong id=(ulong)HistoryDealGetInteger(trans.deal,DEAL_POSITION_ID);
    bool owned=OwnedDeal(trans.deal);
    if(owned && HistoryDealSelect(trans.deal))
     Log("DEAL","deal="+N((long)trans.deal)+" position="+N((long)id)+" price="+DoubleToString(HistoryDealGetDouble(trans.deal,DEAL_PRICE),8)+" lots="+DoubleToString(HistoryDealGetDouble(trans.deal,DEAL_VOLUME),8)+" net="+DoubleToString(DealNet(trans.deal),2)+" commission="+DoubleToString(HistoryDealGetDouble(trans.deal,DEAL_COMMISSION),2)+" swap="+DoubleToString(HistoryDealGetDouble(trans.deal,DEAL_SWAP),2)+" fee="+DoubleToString(HistoryDealGetDouble(trans.deal,DEAL_FEE),2));
   }
  }
 }
 string Status() { return m_status; }
 bool SignalConsumed(const BVPSignal &signal) { return m_day>0 && GlobalVariableCheck(D("S")+"."+N((long)BVPHash(signal.id))); }
 bool OwnedDeal(const ulong deal)
 {
  if(deal==0 || !HistoryDealSelect(deal)) return false;
  ulong id=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
  if(id==0 || !HistorySelectByPosition(id)) return false;
  bool own=false;
  for(int i=0;i<HistoryDealsTotal();i++)
  {
   ulong item=HistoryDealGetTicket(i);
   ENUM_DEAL_TYPE type=(ENUM_DEAL_TYPE)HistoryDealGetInteger(item,DEAL_TYPE);
   if(!TradeDeal(type)) continue;
   ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(item,DEAL_ENTRY);
   if(entry!=DEAL_ENTRY_IN && entry!=DEAL_ENTRY_INOUT) continue;
   if(HistoryDealGetInteger(item,DEAL_MAGIC)!=m_cfg.magic || !OpeningProvenance(item)) return false;
   own=true;
  }
  return own;
 }
 bool PositionMetadata(ulong position_id,BVPSignal &signal,double &planned_risk)
 {
  if(ReadMetadata(PositionFile(position_id),signal,planned_risk)) return true;
  long magic=0; int j=FindLife(position_id);
  if(j>=0 && m_life[j].group_owned && !m_life[j].foreign_in) magic=m_life[j].magic;
  if(magic==0) for(int i=PositionsTotal()-1;i>=0;i--)
  {
   ulong ticket=PositionGetTicket(i);
   if(ticket>0 && (ulong)PositionGetInteger(POSITION_IDENTIFIER)==position_id && GroupMagic(PositionGetInteger(POSITION_MAGIC)))
   { magic=PositionGetInteger(POSITION_MAGIC); break; }
  }
  if(magic==0 || !ReadMetadata(PendingFile(magic),signal,planned_risk) || !signal.valid) return false;
  uint expected=BVPHash(signal.id);
  // Audit callbacks may currently have selected only the closing deal. Select
  // this lifecycle explicitly before comparing its opening intent. This public
  // getter is not called inside the engine's history enumeration loops.
  if(!HistorySelectByPosition(position_id)) return false;
  for(int i=0;i<HistoryDealsTotal();i++)
  {
   ulong deal=HistoryDealGetTicket(i);
   if(HistoryDealGetInteger(deal,DEAL_MAGIC)!=magic || (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY)!=DEAL_ENTRY_IN) continue;
   ulong order=(ulong)HistoryDealGetInteger(deal,DEAL_ORDER);
   string symbol=HistoryDealGetString(deal,DEAL_SYMBOL);
   if(StringFind(signal.id,symbol+":")!=0) continue;
   int setup=0,direction=0; uint hash=0;
   bool parsed=ParseEntryComment(HistoryDealGetString(deal,DEAL_COMMENT),setup,direction,hash);
   if(!parsed) parsed=ParseEntryComment(HistoryOrderGetString(order,ORDER_COMMENT),setup,direction,hash);
   if(!parsed && GlobalVariableCheck(P("I",order)))
   { hash=(uint)G(P("I",order)); setup=(int)G(P("S",order)); direction=(int)G(P("D",order)); parsed=true; }
   if(parsed && hash==expected && setup==(int)signal.setup && direction==signal.direction && OpeningProvenance(deal)) return true;
  }
  return false;
 }
 double DailyPL() { return m_daily; }
 double OpenRisk() { return m_open==DBL_MAX?-1:m_open+Reservations(); }
 double ProposedRisk() { return m_proposed; }
 bool Blocked() { return m_blocked; }
};
#endif
