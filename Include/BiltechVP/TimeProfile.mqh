#ifndef BILTECH_VP_TIME_PROFILE_MQH
#define BILTECH_VP_TIME_PROFILE_MQH
#include "Types.mqh"

// Dates here are wall-clock labels unless explicitly suffixed UTC/broker.
#define BVP_BAD_OFFSET -2147483647
datetime BVPDate(const int y,const int m,const int d)
{
 MqlDateTime x={}; x.year=y; x.mon=m; x.day=d; return StructToTime(x);
}
datetime BVPDay(const datetime t)
{
 MqlDateTime x; TimeToStruct(t,x); return BVPDate(x.year,x.mon,x.day);
}
int BVPSunday(const int y,const int m,const int nth)
{
 MqlDateTime x; TimeToStruct(BVPDate(y,m,1),x); return 1+(7-x.day_of_week)%7+7*(nth-1);
}
int BVPLastSunday(const int y,const int m)
{
 datetime next=(m==12?BVPDate(y+1,1,1):BVPDate(y,m+1,1));
 MqlDateTime x; TimeToStruct(next-86400,x); return x.day-x.day_of_week;
}
// US federal DST from 1970, including the 1974/1975 emergency starts.
int BVPUSOffsetMinutes(const datetime utc)
{
 MqlDateTime x; TimeToStruct(utc,x); int y=x.year;
 if(y<1970 || y>2099) return BVP_BAD_OFFSET;
 int sm=4,sd=BVPLastSunday(y,4),em=10,ed=BVPLastSunday(y,10);
 if(y==1974) { sm=1; sd=6; }
 else if(y==1975) { sm=2; sd=23; }
 else if(y>=2007) { sm=3; sd=BVPSunday(y,3,2); em=11; ed=BVPSunday(y,11,1); }
 else if(y>=1987) sd=BVPSunday(y,4,1);
 datetime a=BVPDate(y,sm,sd)+7*3600,b=BVPDate(y,em,ed)+6*3600;
 return (utc>=a && utc<b)?-240:-300;
}
// Harmonized EU rule, supported from 1996 only: 01:00 UTC transitions.
bool BVPEUIsDST(const datetime utc)
{
 MqlDateTime x; TimeToStruct(utc,x);
 return utc>=BVPDate(x.year,3,BVPLastSunday(x.year,3))+3600 &&
        utc<BVPDate(x.year,10,BVPLastSunday(x.year,10))+3600;
}
string BVPTrim(string s) { StringTrimLeft(s); StringTrimRight(s); return s; }
bool BVPParseMinute(string text,int &minute)
{
 text=BVPTrim(text); string v[];
 if(StringSplit(text,':',v)!=2 || StringLen(v[0])!=2 || StringLen(v[1])!=2) return false;
 for(int i=0;i<2;i++) for(int j=0;j<2;j++)
  if(StringGetCharacter(v[i],j)<'0' || StringGetCharacter(v[i],j)>'9') return false;
 int h=(int)StringToInteger(v[0]),m=(int)StringToInteger(v[1]);
 if(h<0 || h>24 || m<0 || m>59 || (h==24 && m!=0)) return false;
 minute=h*60+m; return true;
}
bool BVPParseDate(string s,datetime &out)
{
 s=BVPTrim(s); StringReplace(s,"-",".");
 if(StringLen(s)!=10 || StringSubstr(s,4,1)!="." || StringSubstr(s,7,1)!=".") return false;
 for(int i=0;i<10;i++) if(i!=4 && i!=7 && (StringGetCharacter(s,i)<'0' || StringGetCharacter(s,i)>'9')) return false;
 int y=(int)StringToInteger(StringSubstr(s,0,4)),m=(int)StringToInteger(StringSubstr(s,5,2)),d=(int)StringToInteger(StringSubstr(s,8,2));
 if(y<1970 || y>2099 || m<1 || m>12 || d<1 || d>31) return false;
 out=BVPDate(y,m,d); MqlDateTime z; TimeToStruct(out,z); return z.year==y && z.mon==m && z.day==d;
}
bool BVPParseUTC(string s,datetime &out)
{
 s=BVPTrim(s); StringReplace(s,"T"," "); StringReplace(s,"Z","");
 if(StringLen(s)!=19 || StringSubstr(s,10,1)!=" ") return false;
 datetime day; if(!BVPParseDate(StringSubstr(s,0,10),day)) return false;
 int minute; if(!BVPParseMinute(StringSubstr(s,11,5),minute) || minute>=1440 || StringSubstr(s,16,1)!=":") return false;
 string sec=StringSubstr(s,17,2);
 for(int j=0;j<2;j++) if(StringGetCharacter(sec,j)<'0' || StringGetCharacter(sec,j)>'9') return false;
 int second=(int)StringToInteger(sec); if(second>59) return false;
 out=day+minute*60+second; return true;
}
struct BVPOffsetRow { datetime start_utc,end_utc; int minutes; };
struct BVPHolidayRow { datetime date; bool closed; int reference_start,reference_end,entry_end; };

class CBVPClock
{
private:
 BVPClockConfig m_cfg; BVPOffsetRow m_offsets[]; BVPHolidayRow m_holidays[];
 bool m_ready; string m_status;
 bool Offset(const datetime utc,int &off)
 {
  if(!m_ready) return false;
  MqlDateTime d; TimeToStruct(utc,d);
  if(d.year<1970 || d.year>2099) { m_status="Clock supports dates 1970..2099"; return false; }
  off=m_cfg.base_offset_minutes;
  if(m_cfg.mode==BROKER_FIXED_UTC) return true;
  if(m_cfg.mode==BROKER_US_DST) { if(BVPUSOffsetMinutes(utc)==-240) off+=m_cfg.dst_delta_minutes; return true; }
  if(m_cfg.mode==BROKER_EU_DST)
  {
   if(d.year<1996) { m_status="EU rule before 1996 requires an offset schedule"; return false; }
   if(BVPEUIsDST(utc)) off+=m_cfg.dst_delta_minutes; return true;
  }
  if(m_cfg.mode==BROKER_OFFSET_SCHEDULE)
  {
   for(int i=0;i<ArraySize(m_offsets);i++) if(utc>=m_offsets[i].start_utc && utc<m_offsets[i].end_utc)
   { off=m_offsets[i].minutes; return true; }
   m_status="UTC date outside broker-offset schedule coverage"; return false;
  }
  m_status="Broker clock unknown: select an explicit offset/rule/schedule"; return false;
 }
 int Holiday(const datetime day)
 {
  for(int i=0;i<ArraySize(m_holidays);i++) if(m_holidays[i].date==day) return i;
  return -1;
 }
 bool DayEligible(const datetime day)
 {
  int h=Holiday(day); if(h>=0) return !m_holidays[h].closed;
  MqlDateTime x; TimeToStruct(day,x); return x.day_of_week>0 && x.day_of_week<6;
 }
 void Windows(const datetime day,int &rs,int &re,int &ee)
 {
  rs=m_cfg.reference_start_minute; re=m_cfg.reference_end_minute; ee=m_cfg.entry_end_minute;
  int h=Holiday(day); if(h<0 || m_holidays[h].closed) return;
  rs=m_holidays[h].reference_start; re=m_holidays[h].reference_end;
  if(m_holidays[h].entry_end>=0) ee=m_holidays[h].entry_end;
 }
 bool ReadOffsets(string &reason)
 {
  int f=FileOpen(m_cfg.offset_file,FILE_READ|FILE_TXT|FILE_ANSI);
  if(f==INVALID_HANDLE) { reason="Cannot read broker-offset CSV in MQL5/Files: "+m_cfg.offset_file; return false; }
  int line=0; bool ok=true;
  while(!FileIsEnding(f))
  {
   string s=BVPTrim(FileReadString(f)); line++;
   if(s=="" || StringSubstr(s,0,1)=="#" || s=="start_utc,end_utc,offset_minutes") continue;
   string a[]; if(StringSplit(s,',',a)!=3 || ArraySize(m_offsets)>=4096) { ok=false; break; }
   BVPOffsetRow row;
   if(!BVPParseUTC(a[0],row.start_utc) || !BVPParseUTC(a[1],row.end_utc) || row.end_utc<=row.start_utc) { ok=false; break; }
   string os=BVPTrim(a[2]);
   for(int j=0;j<StringLen(os);j++) if(!(j==0 && (StringGetCharacter(os,j)=='-' || StringGetCharacter(os,j)=='+')) &&
    (StringGetCharacter(os,j)<'0' || StringGetCharacter(os,j)>'9')) { ok=false; break; }
   if(!ok || StringLen(os)==0 || os=="-" || os=="+") { ok=false; break; }
   row.minutes=(int)StringToInteger(os);
   if(MathAbs(row.minutes)>840) { ok=false; break; }
   int n=ArraySize(m_offsets);
   if(n>0 && row.start_utc<m_offsets[n-1].end_utc) { ok=false; break; }
   ArrayResize(m_offsets,n+1); m_offsets[n]=row;
  }
  FileClose(f);
  if(!ok || ArraySize(m_offsets)==0) { reason=StringFormat("Invalid/overlapping/unsorted broker-offset CSV at line %d",line); return false; }
  return true;
 }
 bool ReadHolidays(string &reason)
 {
  if(m_cfg.holiday_file=="") return true;
  int f=FileOpen(m_cfg.holiday_file,FILE_READ|FILE_TXT|FILE_ANSI);
  if(f==INVALID_HANDLE) { reason="Cannot read holiday CSV in MQL5/Files: "+m_cfg.holiday_file; return false; }
  int line=0; bool ok=true;
  while(!FileIsEnding(f))
  {
   string s=BVPTrim(FileReadString(f)); line++;
   if(s=="" || StringSubstr(s,0,1)=="#" || s=="date,reference_start,reference_end,entry_end") continue;
   string a[]; int fields=StringSplit(s,',',a);
   if(fields<2 || fields>4 || ArraySize(m_holidays)>=4096) { ok=false; break; }
   BVPHolidayRow row; row.entry_end=-1;
   if(!BVPParseDate(a[0],row.date) || Holiday(row.date)>=0) { ok=false; break; }
   row.closed=(BVPTrim(a[1])=="CLOSED");
   row.reference_start=m_cfg.reference_start_minute; row.reference_end=m_cfg.reference_end_minute;
   if(row.closed)
   {
    for(int j=2;j<fields;j++) if(BVPTrim(a[j])!="") { ok=false; break; }
    if(!ok) break;
   }
   if(!row.closed)
   {
    if(fields<3 || !BVPParseMinute(a[1],row.reference_start) || !BVPParseMinute(a[2],row.reference_end) ||
       row.reference_start>=1440 || row.reference_start==row.reference_end) { ok=false; break; }
    if(fields==4 && BVPTrim(a[3])!="" && !BVPParseMinute(a[3],row.entry_end)) { ok=false; break; }
    if(row.entry_end>=0 && (row.entry_end==m_cfg.entry_start_minute ||
       (m_cfg.entry_end_minute>m_cfg.entry_start_minute && row.entry_end<m_cfg.entry_start_minute))) { ok=false; break; }
   }
   int n=ArraySize(m_holidays); ArrayResize(m_holidays,n+1); m_holidays[n]=row;
  }
  FileClose(f); if(!ok) { reason=StringFormat("Invalid/duplicate holiday CSV at line %d",line); return false; }
  return true;
 }
public:
 CBVPClock() { m_ready=false; m_status="Broker clock not initialized"; }
 bool Init(const BVPClockConfig &cfg,string &reason)
 {
  m_ready=false; m_cfg=cfg; ArrayFree(m_offsets); ArrayFree(m_holidays); reason="";
  if(cfg.mode<=BROKER_TIME_UNKNOWN || cfg.mode>BROKER_OFFSET_SCHEDULE) reason="Broker clock unknown: set explicit broker UTC offset/rule/schedule";
  else if(MathAbs(cfg.base_offset_minutes)>840 || cfg.dst_delta_minutes<0 || cfg.dst_delta_minutes>120 ||
          MathAbs(cfg.base_offset_minutes+cfg.dst_delta_minutes)>840) reason="Invalid broker offset/DST delta";
  else if(cfg.lookback_days<1 || cfg.lookback_days>366) reason="Session lookback must be 1..366 days";
  else if(cfg.reference_start_minute<0 || cfg.reference_start_minute>=1440 || cfg.reference_end_minute<0 || cfg.reference_end_minute>1440 ||
          cfg.entry_start_minute<0 || cfg.entry_start_minute>=1440 || cfg.entry_end_minute<0 || cfg.entry_end_minute>1440 ||
          cfg.reference_start_minute==cfg.reference_end_minute || cfg.entry_start_minute==cfg.entry_end_minute) reason="Invalid New York session minutes";
  if(reason!="") { m_status=reason; return false; }
  if(cfg.mode==BROKER_OFFSET_SCHEDULE && !ReadOffsets(reason)) { m_status=reason; return false; }
  if(!ReadHolidays(reason)) { m_status=reason; return false; }
  m_ready=true; m_status="Explicit broker clock configured"; return true;
 }
 bool UTCToBroker(const datetime utc,datetime &broker)
 {
  int off; if(!Offset(utc,off)) return false; broker=utc+off*60; return true;
 }
 bool BrokerToUTC(const datetime broker,datetime &utc)
 {
  if(!m_ready) return false;
  int candidates[]; ArrayResize(candidates,0);
  if(m_cfg.mode==BROKER_OFFSET_SCHEDULE)
  {
   int matches=0; datetime found=0;
   for(int i=0;i<ArraySize(m_offsets);i++)
   {
    datetime t=broker-m_offsets[i].minutes*60;
    if(t>=m_offsets[i].start_utc && t<m_offsets[i].end_utc) { found=t; matches++; }
   }
   if(matches!=1) { m_status=(matches>1?"Ambiguous broker schedule wall time":"Broker wall time outside schedule coverage"); return false; }
   utc=found; return true;
  }
  else
  {
   ArrayResize(candidates,2); candidates[0]=m_cfg.base_offset_minutes; candidates[1]=m_cfg.base_offset_minutes+m_cfg.dst_delta_minutes;
  }
  int matches=0; datetime found=0;
  for(int i=0;i<ArraySize(candidates);i++)
  {
   bool duplicate=false; for(int j=0;j<i;j++) if(candidates[j]==candidates[i]) { duplicate=true; break; }
   if(duplicate) continue;
   datetime t=broker-candidates[i]*60; int off;
   if(Offset(t,off) && off==candidates[i]) { found=t; matches++; }
  }
  if(matches!=1) { m_status=(matches>1?"Ambiguous broker DST wall time; trading blocked":"Unmapped broker wall time; check offset coverage"); return false; }
  utc=found; return true;
 }
 datetime UTCToNY(const datetime utc)
 {
  int off=BVPUSOffsetMinutes(utc); if(off==BVP_BAD_OFFSET) { m_status="New York conversion supports 1970..2099"; return 0; }
  return utc+off*60;
 }
 bool NYToUTC(const datetime ny,datetime &utc)
 {
  datetime a=ny+300*60,b=ny+240*60; int matches=0;
  if(BVPUSOffsetMinutes(a)==-300) { utc=a; matches++; }
  if(BVPUSOffsetMinutes(b)==-240) { utc=b; matches++; }
  if(matches!=1) { m_status="Ambiguous/nonexistent New York DST wall time"; return false; } return true;
 }
 bool DayContext(const datetime utc,datetime &nyday,datetime &day_start_broker,string &reason)
 {
  datetime ny=UTCToNY(utc),u; if(ny==0) { reason=m_status; return false; }
  nyday=BVPDay(ny);
  if(!NYToUTC(nyday,u) || !UTCToBroker(u,day_start_broker)) { reason=m_status; return false; }
  reason=""; return true;
 }
 bool EntryWindow(const datetime utc)
 {
  if(!m_ready) return false;
  datetime ny=UTCToNY(utc); if(ny==0) return false;
  datetime today=BVPDay(ny);
  // Evaluate each anchor's own overrides; tomorrow's default close must not
  // truncate yesterday's custom overnight close.
  for(int d=0;d<=1;d++)
  {
   datetime day=today-d*86400; if(!DayEligible(day)) continue;
   int rs,re,ee; Windows(day,rs,re,ee);
   datetime a=day+m_cfg.entry_start_minute*60,b=day+ee*60;
   if(ee<=m_cfg.entry_start_minute) b+=86400;
   if(ny>=a && ny<b) return true;
  }
  return false;
 }
 bool PastEntryEnd(const datetime utc)
 {
  if(!m_ready) return false;
  datetime ny=UTCToNY(utc); if(ny==0) return false;
  if(EntryWindow(utc)) return false;
  if(!DayEligible(BVPDay(ny))) return true;
  datetime day=BVPDay(ny);
  if(ny<day+m_cfg.entry_start_minute*60) day-=86400;
  int rs,re,ee; Windows(day,rs,re,ee);
  datetime end=day+ee*60+(ee<=m_cfg.entry_start_minute?86400:0);
  return ny>=end;
 }
 bool PreviousSession(const datetime now_utc,const int lookback_index,BVPProfile &session,string &reason)
 {
  ZeroMemory(session); reason="";
  if(!m_ready || lookback_index<0) { reason=m_status; return false; }
  datetime ny=UTCToNY(now_utc); if(ny==0) { reason=m_status; return false; }
  datetime day=BVPDay(ny); int eligible=0;
  for(int d=0;d<=m_cfg.lookback_days;d++)
  {
   datetime candidate=day-d*86400; if(!DayEligible(candidate)) continue;
   int rs,re,ee; Windows(candidate,rs,re,ee);
   datetime a,b; if(!NYToUTC(candidate+rs*60,a) || !NYToUTC(candidate+re*60+(re<=rs?86400:0),b)) { reason=m_status; return false; }
   if(b>now_utc || a>=b) continue;
   if(eligible++!=lookback_index) continue;
   if(!UTCToBroker(a,session.start_broker) || !UTCToBroker(b,session.end_broker)) { reason=m_status; return false; }
   session.ny_date=candidate; session.start_utc=a; session.end_utc=b;
   session.status="Completed session candidate; history validation pending"; return true;
  }
  reason="No completed eligible reference within maximum lookback"; return false;
 }
 string Status() { return m_status; }
};

// Pure deterministic histogram: points or OHLC ranges; the last bin includes max.
bool BVPBuildProfile(const double &prices[],const double &weights[],const double &lows[],const double &highs[],
                     const double tick,const int requested_rows,const double value_percent,const bool ranges,
                     BVPProfile &out,string &reason)
{
 out.valid=false; reason=""; int n=ArraySize(weights);
 if(n<1 || ArraySize(prices)!=n || (ranges && (ArraySize(lows)!=n || ArraySize(highs)!=n)) ||
    !BVPFinitePositive(tick) || requested_rows<1 || requested_rows>10000 || !MathIsValidNumber(value_percent) || value_percent<=0 || value_percent>100)
 { reason="Invalid profile inputs"; return false; }
 double low=DBL_MAX,high=-DBL_MAX,total=0;
 for(int i=0;i<n;i++)
 {
  double a=(ranges?lows[i]:prices[i]),b=(ranges?highs[i]:prices[i]);
  if(!BVPFinitePositive(a) || !BVPFinitePositive(b) || a>b || !BVPFinitePositive(weights[i]))
  { reason="Profile contains invalid price/range/weight"; return false; }
  low=MathMin(low,a); high=MathMax(high,b); total+=weights[i];
 }
 if(!BVPFinitePositive(total)) { reason="Invalid total profile weight"; return false; }
 double lower=BVPTickFloor(low,tick),span=MathMax(0,high-lower);
 double width=MathMax(1.0,MathCeil(span/(requested_rows*tick)-1e-10))*tick;
 if(!MathIsValidNumber(lower) || !MathIsValidNumber(span) || !BVPFinitePositive(width)) { reason="Profile price/tick scale exceeds numeric bounds"; return false; }
 int rows=(int)MathMax(1.0,MathCeil(span/width-1e-10));
 double bins[]; if(ArrayResize(bins,rows)!=rows) { reason="Profile memory allocation failed"; return false; } ArrayInitialize(bins,0);
 for(int i=0;i<n;i++)
 {
  double a=(ranges?lows[i]:prices[i]),b=(ranges?highs[i]:prices[i]);
  if(!ranges || b==a)
  {
   int k=(int)MathFloor((a-lower)/width+1e-10); k=MathMax(0,MathMin(rows-1,k)); bins[k]+=weights[i];
  }
  else
  {
   int first=MathMax(0,(int)MathFloor((a-lower)/width)),last=MathMin(rows-1,(int)MathFloor((b-lower)/width));
   double allocated=0;
   for(int j=first;j<=last;j++)
   {
    double overlap=MathMax(0,MathMin(b,lower+(j+1)*width)-MathMax(a,lower+j*width));
    double add=weights[i]*overlap/(b-a); bins[j]+=add; allocated+=add;
   }
   // Compensate only floating arithmetic residue, preserving total weight.
   if(last>=first) bins[last]+=weights[i]-allocated;
  }
 }
 int poc=0; double mid=(rows-1)*0.5;
 for(int j=1;j<rows;j++)
 {
  if(bins[j]>bins[poc] || (bins[j]==bins[poc] && MathAbs(j-mid)<MathAbs(poc-mid))) poc=j;
 }
 int left=poc,right=poc; double accum=bins[poc],target=total*value_percent/100.0;
 while(accum<target && (left>0 || right<rows-1))
 {
  if(left>0 && (right>=rows-1 || bins[left-1]>=bins[right+1])) { left--; accum+=bins[left]; }
  else { right++; accum+=bins[right]; }
 }
 out.lower=lower; out.bin_width=width; out.rows=rows; out.total_weight=total;
 out.poc=lower+(poc+0.5)*width; out.val=lower+left*width; out.vah=lower+(right+1)*width;
 out.events=n; out.valid=true; out.status="Deterministic frozen profile"; return true;
}

// Source-event filters are public so deterministic tests exercise production.
bool BVPQuoteEvent(const MqlTick &tick,bool &have_bid,double &previous_bid)
{
 if(!BVPFinitePositive(tick.bid)) { have_bid=false; return false; }
 bool changed=(tick.flags&TICK_FLAG_BID)!=0 && (!have_bid || tick.bid!=previous_bid);
 previous_bid=tick.bid; have_bid=true; return changed;
}
bool BVPTradeEvent(const MqlTick &tick,double &price,double &weight)
{
 bool event=(tick.flags&(TICK_FLAG_LAST|TICK_FLAG_VOLUME|TICK_FLAG_BUY|TICK_FLAG_SELL))!=0;
 weight=(tick.volume_real>0?tick.volume_real:(double)tick.volume); price=tick.last;
 return event && BVPFinitePositive(price) && BVPFinitePositive(weight);
}

// One chunk per timer. Calls are bounded in amount, not guaranteed latency:
// terminal CopyTicksRange/CopyRates can synchronously wait for network history.
class CBVPProfileLoader
{
private:
 string m_symbol,m_status; BVPProfileConfig m_cfg; BVPProfile m_session;
 bool m_busy,m_finished,m_prepared,m_has_bid; int m_retry,m_count,m_minutes;
 long m_cursor,m_end,m_chunk_ms,m_active_minute; double m_prev_bid,m_close,m_minute_bid,m_minute_close;
 int m_minute_retry; bool m_minute_has_bid;
 double m_prices[],m_weights[],m_lows[],m_highs[]; bool m_expected[],m_covered[];
 MqlTick m_ticks[65536];
 void Fail(const string reason)
 {
  m_busy=false; m_finished=true; m_session.valid=false; m_status=reason; m_session.status=reason;
 }
 bool Append(const double p,const double w,const double lo,const double hi)
 {
  if(m_count>=m_cfg.max_events) { Fail("Profile event memory limit exceeded; increase validated MaxProfileEvents"); return false; }
  int n=m_count+1;
  if(ArrayResize(m_prices,n,4096)!=n || ArrayResize(m_weights,n,4096)!=n ||
     ArrayResize(m_lows,n,4096)!=n || ArrayResize(m_highs,n,4096)!=n) { Fail("Profile memory allocation failed"); return false; }
  m_prices[m_count]=p; m_weights[m_count]=w; m_lows[m_count]=lo; m_highs[m_count]=hi; m_count++; return true;
 }
 bool TradingMinute(const datetime broker,bool &known)
 {
  MqlDateTime b; TimeToStruct(broker,b); int second=b.hour*3600+b.min*60;
  bool any=false,open=false;
  for(int daypass=0;daypass<2;daypass++)
  {
   int weekday=(b.day_of_week-daypass+7)%7;
   for(uint i=0;i<32;i++)
   {
    datetime from,to; if(!SymbolInfoSessionTrade(m_symbol,(ENUM_DAY_OF_WEEK)weekday,i,from,to)) break;
    any=true; long a=(long)from%86400,z=(long)to%86400;
    // 00:00->24:00 often arrives as 00:00->00:00; a supplied
    // equal pair is interpreted as a complete day, never a missing record.
    if(daypass==0 && (a==z || (a<z && second>=a && second<z) || (a>z && second>=a))) open=true;
    if(daypass==1 && a>z && second<z) open=true;
   }
  }
  // Distinguish a closed weekday from a symbol exposing no schedule at all.
  if(!any)
  {
   for(int wd=0;wd<7;wd++) { datetime a,z; if(SymbolInfoSessionTrade(m_symbol,(ENUM_DAY_OF_WEEK)wd,0,a,z)) { any=true; break; } }
  }
  known=any; return open;
 }
 bool Prepare(CBVPClock &clock)
 {
  long seconds=(long)m_session.end_utc-(long)m_session.start_utc;
  if(seconds<=0 || seconds>90000 || seconds%60!=0) { Fail("Reference duration must be a positive whole number of minutes, at most 25h"); return false; }
  m_minutes=(int)(seconds/60);
  ArrayResize(m_expected,m_minutes); ArrayResize(m_covered,m_minutes); ArrayInitialize(m_expected,false); ArrayInitialize(m_covered,false);
  m_session.expected_minutes=0;
  for(int i=0;i<m_minutes;i++)
  {
   datetime u=m_session.start_utc+i*60,b,back;
   if(!clock.UTCToBroker(u,b) || !clock.BrokerToUTC(b,back) || back!=u)
   { Fail("Reference crosses ambiguous/unmapped broker clock: "+clock.Status()); return false; }
   // CopyRates works in broker wall time: never combine a repeated/skipped clock hour.
   if(b!=m_session.start_broker+i*60) { Fail("Reference crosses broker offset transition; choose an unambiguous window"); return false; }
   bool known; m_expected[i]=TradingMinute(b,known);
   if(!known) { Fail("Broker supplied no symbol trading-session metadata"); return false; }
   if(m_expected[i]) m_session.expected_minutes++;
  }
  if(m_session.expected_minutes==0) { Fail("Reference has no expected symbol trading minutes"); return false; }
  m_prepared=true; return true;
 }
 bool Retry(const string reason,const bool shrink)
 {
  m_retry++;
  if(shrink && m_chunk_ms>1000) m_chunk_ms=MathMax(1000,m_chunk_ms/2);
  if(m_retry>m_cfg.max_retries) { Fail(reason+"; bounded history retries exhausted"); return false; }
  m_status=StringFormat("History retry %d/%d: %s",m_retry,m_cfg.max_retries,reason); return false;
 }
 void Cover(const datetime utc)
 {
  int i=(int)((utc-m_session.start_utc)/60); if(i>=0 && i<m_minutes) m_covered[i]=true;
 }
 void Complete()
 {
  int covered=0,longest=0,run=0;
  for(int i=0;i<m_minutes;i++)
  {
   if(!m_expected[i]) { run=0; continue; }
   if(m_covered[i]) { covered++; run=0; } else { run++; longest=MathMax(longest,run); }
  }
  m_session.covered_minutes=covered; m_session.gap_minutes=longest; m_session.events=m_count;
  double percent=100.0*covered/m_session.expected_minutes;
  if(percent+1e-9<m_cfg.minimum_coverage_percent || longest>m_cfg.maximum_gap_minutes)
  { Fail(StringFormat("Incomplete %s: %.2f%% minute coverage (%d/%d), longest gap %d",BVPModeName(m_cfg.mode),percent,covered,m_session.expected_minutes,longest)); return; }
  if(m_count<m_cfg.min_events) { Fail(StringFormat("Inadequate %s: %d events; require %d",BVPModeName(m_cfg.mode),m_count,m_cfg.min_events)); return; }
  string reason; double tick=SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_SIZE);
  if(!BVPBuildProfile(m_prices,m_weights,m_lows,m_highs,tick,m_cfg.requested_rows,m_cfg.value_percent,m_cfg.mode==M1_APPROXIMATION,m_session,reason)) { Fail(reason); return; }
  m_session.previous_close=m_close; m_session.mode=m_cfg.mode;
  m_status=StringFormat("%s: frozen %d rows, %d events, %.2f%% minute coverage, gap %d",BVPModeName(m_cfg.mode),m_session.rows,m_count,percent,longest);
  m_session.status=m_status; m_busy=false; m_finished=true;
 }
 void TickChunk(CBVPClock &clock)
 {
  long minute_start=(m_cursor/60000)*60000;
  if(m_active_minute!=minute_start)
  {
   m_active_minute=minute_start; m_minute_retry=0;
   m_minute_bid=m_prev_bid; m_minute_close=m_close; m_minute_has_bid=m_has_bid;
  }
  long until=MathMin(MathMin(m_end,m_cursor+m_chunk_ms),minute_start+60000),from=m_cursor;
  // Tick timestamps supplied by MT5 are broker times, just as its bars.
  datetime a,b;
  if(!clock.UTCToBroker((datetime)(from/1000),a) || !clock.UTCToBroker((datetime)((until-1)/1000),b)) { Fail(clock.Status()); return; }
  ulong ba=(ulong)((long)a*1000+from%1000),bz=(ulong)((long)b*1000+(until-1)%1000);
  ResetLastError(); int n=CopyTicksRange(m_symbol,m_ticks,COPY_TICKS_ALL,ba,bz); int err=GetLastError();
  if(n<0 || err!=0 || n>MathMin(65536,m_cfg.max_chunk_ticks))
  { Retry(StringFormat("CopyTicksRange returned %d, error %d (partial chunk discarded)",n,err),true); return; }
  long previous=-1;
  for(int i=0;i<n;i++)
  {
   if(m_ticks[i].time_msc<(long)ba || m_ticks[i].time_msc>(long)bz || m_ticks[i].time_msc<previous)
   { Retry("Unordered/out-of-range tick chunk discarded",false); return; }
   previous=m_ticks[i].time_msc;
  }
  bool available=false;
  for(int i=0;i<n;i++)
  {
   if(m_cfg.mode==QUOTE_TICK_PROFILE) { if(BVPFinitePositive(m_ticks[i].bid)) available=true; }
   else { double p,w; if(BVPTradeEvent(m_ticks[i],p,w)) available=true; }
  }
  int minute=(int)((minute_start/1000-m_session.start_utc)/60);
  if(until==minute_start+60000 && minute>=0 && minute<m_minutes && m_expected[minute] && !m_covered[minute] && !available)
  {
   // Earlier subchunks in an entirely empty minute have appended no events.
   // Replay its whole interval to catch error=0 incomplete archival responses.
   // Checkpoint comparison state as invalid snapshots could have reset it.
   m_minute_retry++;
   if(m_minute_retry<=m_cfg.max_retries)
   {
    m_cursor=minute_start; m_prev_bid=m_minute_bid; m_close=m_minute_close; m_has_bid=m_minute_has_bid;
    m_status=StringFormat("Missing expected tick minute: replay %d/%d (no events committed)",m_minute_retry,m_cfg.max_retries); return;
   }
   if(m_cfg.minimum_coverage_percent>=100 || m_cfg.maximum_gap_minutes==0)
   { Fail("Missing expected tick minute after bounded full-minute replays; strict coverage blocks profile"); return; }
   // An explicitly relaxed coverage policy can tolerate the known missing
   // minute after retries. The complete-session percent/gap checks still apply.
  }
  // Whole chunk commits once. No timestamp deduplication: legitimate multiple
  // trade/Bid events in the same millisecond remain distinct and ordered.
  for(int i=0;i<n;i++)
  {
   MqlTick t=m_ticks[i]; datetime u=(datetime)((m_cursor+(t.time_msc-(long)ba))/1000);
   if(m_cfg.mode==QUOTE_TICK_PROFILE)
   {
    bool changed=BVPQuoteEvent(t,m_has_bid,m_prev_bid);
    if(!BVPFinitePositive(t.bid)) continue;
    Cover(u); m_close=t.bid;
    if(changed && !Append(t.bid,1,t.bid,t.bid)) return;
   }
   else
   {
    double price,volume; if(!BVPTradeEvent(t,price,volume)) continue;
    Cover(u); m_close=price; if(!Append(price,volume,price,price)) return;
   }
  }
  m_cursor=until; m_retry=0;
 }
 void BarChunk(CBVPClock &clock)
 {
  long chunk=MathMax(60000,(m_chunk_ms/60000)*60000),until=MathMin(m_end,m_cursor+chunk);
  datetime a,b; if(!clock.UTCToBroker((datetime)(m_cursor/1000),a) || !clock.UTCToBroker((datetime)(until/1000),b)) { Fail(clock.Status()); return; }
  MqlRates rates[]; ArraySetAsSeries(rates,false); ResetLastError();
  int n=CopyRates(m_symbol,PERIOD_M1,a,b-1,rates),err=GetLastError();
  if(n<0 || err!=0) { Retry(StringFormat("CopyRates returned %d, error %d; partial chunk discarded",n,err),false); return; }
  datetime previous=0;
  for(int i=0;i<n;i++)
  {
   if(rates[i].time<a || rates[i].time>=b || rates[i].time%60!=0 || (i>0 && rates[i].time<=previous))
   { Retry("Unordered/out-of-range M1 chunk discarded",false); return; } previous=rates[i].time;
  }
  int wanted=0,present=0;
  int first=(int)((m_cursor/1000-m_session.start_utc)/60),last=(int)((until/1000-m_session.start_utc)/60);
  for(int j=first;j<last;j++) if(j>=0 && j<m_minutes && m_expected[j]) wanted++;
  for(int i=0;i<n;i++)
  {
   int j=first+(int)((rates[i].time-a)/60);
   if(j>=0 && j<m_minutes && m_expected[j] && rates[i].tick_volume>0 &&
      BVPFinitePositive(rates[i].close) && BVPFinitePositive(rates[i].low) && BVPFinitePositive(rates[i].high) && rates[i].low<=rates[i].high) present++;
  }
  if(present<wanted)
  {
   if(m_retry<m_cfg.max_retries) { Retry(StringFormat("Incomplete M1 chunk: %d/%d expected trading minutes; chunk discarded",present,wanted),false); return; }
   if(m_cfg.minimum_coverage_percent>=100 || m_cfg.maximum_gap_minutes==0)
   { Fail(StringFormat("Incomplete M1 chunk after bounded retries: %d/%d expected minutes; strict coverage blocks profile",present,wanted)); return; }
  }
  for(int i=0;i<n;i++)
  {
   MqlRates r=rates[i]; if(r.tick_volume<=0 || !BVPFinitePositive(r.close) || !BVPFinitePositive(r.low) || !BVPFinitePositive(r.high) || r.low>r.high) continue;
   datetime u=(datetime)(m_cursor/1000)+(r.time-a); Cover(u); m_close=r.close;
   if(!Append(r.close,(double)r.tick_volume,r.low,r.high)) return;
  }
  m_cursor=until; m_retry=0;
 }
public:
 CBVPProfileLoader() { m_busy=false; m_finished=false; m_prepared=false; m_status="Profile loader not initialized"; }
 void Init(const string symbol,const BVPProfileConfig &cfg) { m_symbol=symbol; m_cfg=cfg; Reset(); }
 void Reset()
 {
  m_busy=false; m_finished=false; m_prepared=false; m_has_bid=false; m_count=0; m_retry=0; m_prev_bid=0; m_close=0;
  m_active_minute=-1; m_minute_retry=0; m_minute_has_bid=false; m_minute_bid=0; m_minute_close=0;
  ArrayFree(m_prices); ArrayFree(m_weights); ArrayFree(m_lows); ArrayFree(m_highs); ArrayFree(m_expected); ArrayFree(m_covered);
  ZeroMemory(m_session); m_status="Profile pending";
 }
 bool Busy() { return m_busy; }
 void Start(const BVPProfile &session)
 {
  Reset(); m_session=session; m_session.valid=false; m_session.mode=m_cfg.mode;
  if(m_cfg.mode<QUOTE_TICK_PROFILE || m_cfg.mode>M1_APPROXIMATION || m_cfg.chunk_seconds<1 || m_cfg.chunk_seconds>3600 || m_cfg.max_chunk_ticks<1 || m_cfg.max_events<1 || m_cfg.max_events>2000000 ||
     m_cfg.max_retries<0 || m_cfg.max_retries>100 || m_cfg.min_events<1 || m_cfg.minimum_coverage_percent<=0 || m_cfg.minimum_coverage_percent>100 ||
     !MathIsValidNumber(m_cfg.minimum_coverage_percent) || m_cfg.min_events>m_cfg.max_events || m_cfg.maximum_gap_minutes<0 || m_cfg.requested_rows<1 ||
     m_cfg.requested_rows>10000 || !MathIsValidNumber(m_cfg.value_percent) || m_cfg.value_percent<=0 || m_cfg.value_percent>100)
  { Fail("Invalid bounded profile-loader configuration"); return; }
  m_cursor=(long)session.start_utc*1000; m_end=(long)session.end_utc*1000; m_chunk_ms=(long)m_cfg.chunk_seconds*1000;
  m_busy=true; m_status="Preparing expected symbol trading minutes";
 }
 void Step(CBVPClock &clock)
 {
  if(!m_busy) return;
  if(!m_prepared) { Prepare(clock); return; }
  if(!SeriesInfoInteger(m_symbol,PERIOD_M1,SERIES_SYNCHRONIZED))
  {
   MqlRates seed[]; ResetLastError(); CopyRates(m_symbol,PERIOD_M1,m_session.start_broker,1,seed);
   Retry("M1 series synchronization pending",false); return;
  }
  if(m_cursor>=m_end) { Complete(); return; }
  long before=m_cursor;
  if(m_cfg.mode==M1_APPROXIMATION) BarChunk(clock); else TickChunk(clock);
  if(m_busy && m_cursor>before) m_status=StringFormat("Loading %s: %.1f%%, %d events",BVPModeName(m_cfg.mode),100.0*(m_cursor-(long)m_session.start_utc*1000)/(m_end-(long)m_session.start_utc*1000),m_count);
 }
 bool Finished() { return m_finished; }
 bool Get(BVPProfile &out) { out=m_session; return m_finished && out.valid; }
 string Status() { return m_status; }
};
#endif
