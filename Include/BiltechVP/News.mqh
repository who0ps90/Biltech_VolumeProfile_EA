#ifndef BILTECH_VP_NEWS_MQH
#define BILTECH_VP_NEWS_MQH
#include "TimeProfile.mqh"
struct BVPNewsEvent { datetime start_utc,end_utc; bool fomc; string title; };
class CBVPNews
{
private:
 ENUM_NEWS_MODE m_mode; string m_file,m_status; bool m_fomc,m_allow_synthetic,m_valid;
 int m_before,m_after,m_fb,m_fa; datetime m_from,m_to,m_refresh;
 BVPNewsEvent m_events[];
 bool Add(datetime start,datetime end,bool fomc,string title)
 {
  int n=ArraySize(m_events); if(n>=10000) { m_status="News event bound exceeded"; return false; }
  ArrayResize(m_events,n+1); m_events[n].start_utc=start; m_events[n].end_utc=end;
  m_events[n].fomc=fomc; m_events[n].title=title; return true;
 }
 bool LoadCSV()
 {
  m_valid=false; ArrayResize(m_events,0); m_from=0; m_to=0;
  int f=FileOpen(m_file,FILE_READ|FILE_TXT|FILE_ANSI);
  if(f==INVALID_HANDLE) { m_status="Required historical news CSV missing: "+m_file; return false; }
  // Exactly one continuous coverage declaration, no automatic extrapolation.
  int line=0; bool good=true;
  while(!FileIsEnding(f))
  {
   string row=BVPTrim(FileReadString(f)); line++; if(row=="") continue;
   if(line==1 && row=="kind,start_utc,end_utc,currency,impact,fomc,title,synthetic") continue;
   string fields[];
   if(StringSplit(row,',',fields)!=8) { good=false; m_status="News CSV needs exactly eight unquoted comma-separated columns at line "+IntegerToString(line); break; }
   for(int j=0;j<8;j++) fields[j]=BVPTrim(fields[j]);
   string kind=fields[0],a=fields[1],b=fields[2],currency=fields[3],impact=fields[4];
   string fomc=fields[5],title=fields[6],synthetic=fields[7];
   if(synthetic!="0" && synthetic!="1") { good=false; m_status="News CSV requires synthetic=0 or 1"; break; }
   if(synthetic=="1" && !m_allow_synthetic) { good=false; m_status="Synthetic news fixture rejected; supply verified historical data"; break; }
   datetime start,end;
   if(!BVPParseUTC(a,start) || !BVPParseUTC(b,end) || end<start) { good=false; m_status="Invalid news UTC timestamp at line "+IntegerToString(line); break; }
   if(kind=="COVERAGE")
   {
    if(m_from!=0 || end<=start || currency!="USD") { good=false; m_status="News CSV needs one USD continuous COVERAGE row"; break; }
    m_from=start; m_to=end;
   }
   else if(kind=="EVENT")
   {
    if(fomc!="0" && fomc!="1") { good=false; m_status="Invalid FOMC flag"; break; }
    if(currency=="USD" && (impact=="HIGH" || (m_fomc && fomc=="1")))
      if(!Add(start,end,fomc=="1",title)) { good=false; break; }
   }
   else { good=false; m_status="Unknown news row kind"; break; }
  }
  FileClose(f);
  if(!good) return false;
  if(m_from<=0 || m_to<=m_from) { m_status="News CSV has no coverage declaration"; return false; }
  for(int i=0;i<ArraySize(m_events);i++)
   if(m_events[i].start_utc<m_from || m_events[i].end_utc>=m_to) { m_status="News event outside declared coverage"; return false; }
  m_valid=true; m_status="Historical CSV coverage declared (provider must verify completeness)"; return true;
 }
public:
 void Init(ENUM_NEWS_MODE mode,string filename,int before,int after,bool fomc,int fb,int fa,bool allow_synthetic)
 {
  m_mode=mode; m_file=filename; m_before=before; m_after=after; m_fomc=fomc; m_fb=fb; m_fa=fa;
  m_allow_synthetic=allow_synthetic; m_valid=false; m_refresh=0; m_from=0; m_to=0;
  m_status="News not loaded"; ArrayResize(m_events,0);
  if(mode==NEWS_DISABLED_RESEARCH) { m_valid=true; m_status="NEWS DISABLED — separately labelled research"; }
  else if(mode==NEWS_HISTORICAL_CSV) LoadCSV();
 }
 void Refresh(datetime utc,CBVPClock &clock)
 {
  if(m_mode!=NEWS_MT5_CALENDAR || utc<m_refresh) return;
  m_refresh=utc+60; m_valid=false;
  if((bool)MQLInfoInteger(MQL_TESTER)) { m_status="MT5 calendar unavailable for backtest; supply historical news CSV or explicitly disable"; return; }
  datetime from=utc-86400,to=utc+86400,bs,be;
  if(!clock.UTCToBroker(from,bs) || !clock.UTCToBroker(to,be)) { m_status="News server timezone conversion unavailable"; return; }
  MqlCalendarValue values[]; ResetLastError();
  int n=CalendarValueHistory(values,bs,be,"","USD"),error=GetLastError();
  if(n<0 || error!=0) { m_status="Calendar incomplete/error "+IntegerToString(error); return; }
  ArrayResize(m_events,0);
  for(int i=0;i<n;i++)
  {
   MqlCalendarEvent event;
   if(!CalendarEventById(values[i].event_id,event)) { m_status="Calendar event metadata missing"; return; }
   string label=event.name+" "+event.event_code; StringToUpper(label);
   bool fomc=(StringFind(label,"FOMC")>=0 || StringFind(label,"FEDERAL OPEN MARKET")>=0);
   if(event.importance!=CALENDAR_IMPORTANCE_HIGH && !(m_fomc && fomc)) continue;
   datetime start,end;
   if(!clock.BrokerToUTC(values[i].time,start)) { m_status="Ambiguous calendar server timestamp"; return; }
   end=start;
   if(event.time_mode!=CALENDAR_TIMEMODE_DATETIME)
   {
    MqlDateTime d; TimeToStruct(values[i].time,d); d.hour=0; d.min=0; d.sec=0;
    datetime serverday=StructToTime(d);
    if(!clock.BrokerToUTC(serverday,start) || !clock.BrokerToUTC(serverday+86400,end)) { m_status="Calendar untimed event conversion invalid"; return; }
   }
   if(!Add(start,end,fomc,event.name)) return;
  }
  m_from=from; m_to=to; m_valid=true; m_status="MT5 USD calendar refreshed";
 }
 bool Allowed(datetime utc,string &reason)
 {
  if(m_mode==NEWS_DISABLED_RESEARCH) { reason=m_status; return true; }
  if(!m_valid) { reason=m_status; return false; }
  int pre=MathMax(m_before,m_fomc?m_fb:0),post=MathMax(m_after,m_fomc?m_fa:0);
  if(utc-pre*60<m_from || utc+post*60>=m_to) { reason="Required news coverage missing around entry time"; return false; }
  if(m_mode==NEWS_MT5_CALENDAR && utc>=m_refresh+120) { reason="Calendar refresh stale"; return false; }
  for(int i=0;i<ArraySize(m_events);i++)
  {
   int before=m_events[i].fomc && m_fomc?m_fb:m_before;
   int after=m_events[i].fomc && m_fomc?m_fa:m_after;
   if(utc>=m_events[i].start_utc-before*60 && utc<=m_events[i].end_utc+after*60)
   { reason="News exclusion: "+m_events[i].title; return false; }
  }
  reason=m_status; return true;
 }
 string Status() { return m_status; }
};
#endif
