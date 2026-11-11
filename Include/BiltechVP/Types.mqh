#ifndef BILTECH_VP_TYPES_MQH
#define BILTECH_VP_TYPES_MQH
#define BVP_VERSION "1.00"
enum ENUM_ASSET_PRESET { ASSET_UNSELECTED=0, GOLD=1, NASDAQ100=2, US30=3 };
enum ENUM_PROFILE_MODE { QUOTE_TICK_PROFILE=0, TRADE_VOLUME_PROFILE=1, M1_APPROXIMATION=2 };
enum ENUM_BROKER_CLOCK { BROKER_TIME_UNKNOWN=0, BROKER_FIXED_UTC=1, BROKER_US_DST=2, BROKER_EU_DST=3, BROKER_OFFSET_SCHEDULE=4 };
enum ENUM_NEWS_MODE { NEWS_MT5_CALENDAR=0, NEWS_HISTORICAL_CSV=1, NEWS_DISABLED_RESEARCH=2 };
enum ENUM_SETUP { SETUP_NONE=0, VALUE_REENTRY=1, BREAKOUT_CONTINUATION=2, POC_BOUNCE=3 };
struct BVPProfile
{
 bool valid; datetime start_utc,end_utc,start_broker,end_broker,ny_date;
 double poc,vah,val,previous_close,lower,bin_width,total_weight;
 int rows,expected_minutes,covered_minutes,gap_minutes; long events;
 ENUM_PROFILE_MODE mode; string status;
};
struct BVPSignal
{
 bool valid; string id; ENUM_SETUP setup; int direction;
 datetime bar_time,expires_broker; double close,atr,buffer,stop,poc,vah,val;
};
struct BVPClockConfig
{
 ENUM_BROKER_CLOCK mode; int base_offset_minutes,dst_delta_minutes;
 string offset_file,holiday_file; int lookback_days;
 int reference_start_minute,reference_end_minute,entry_start_minute,entry_end_minute;
};
struct BVPProfileConfig
{
 ENUM_PROFILE_MODE mode; int requested_rows; double value_percent;
 int chunk_seconds,max_chunk_ticks,max_events,max_retries,min_events;
 double minimum_coverage_percent; int maximum_gap_minutes;
};
struct BVPSignalConfig
{
 bool enable_reentry,enable_breakout,enable_bounce,reentry_space_filter;
 int reentry_bars,retest_bars,confirmation_bars; double buffer_atr,target_r;
};
struct BVPRiskConfig
{
 long group_id,magic; bool allow_live,close_on_daily_loss;
 double risk_percent,aggregate_percent,daily_loss_percent;
 int max_losses,max_symbol_entries,max_setup_direction_entries;
 double commission_per_lot_round_turn,slippage_ticks,fill_risk_tolerance_percent;
 double spread_atr_fraction,spread_stop_fraction,max_entry_drift_atr;
 double target_r; bool reentry_space_filter;
 int quote_max_age_seconds,deviation_points; string parameter_id;
};
string BVPSetupName(const ENUM_SETUP s)
{
 if(s==VALUE_REENTRY) return "VALUE_REENTRY";
 if(s==BREAKOUT_CONTINUATION) return "BREAKOUT_CONTINUATION";
 if(s==POC_BOUNCE) return "POC_BOUNCE";
 return "NONE";
}
string BVPModeName(const ENUM_PROFILE_MODE m)
{
 if(m==QUOTE_TICK_PROFILE) return "Bid quote-activity profile";
 if(m==TRADE_VOLUME_PROFILE) return "Broker-supplied trade-volume profile";
 return "M1 approximate tick-volume profile";
}
uint BVPHash(const string s)
{
 uint h=2166136261;
 for(int i=0;i<StringLen(s);i++) { h^=(uint)StringGetCharacter(s,i); h*=16777619; }
 return h;
}
double BVPTickFloor(const double p,const double tick) { return MathFloor(p/tick+1e-9)*tick; }
double BVPTickCeil(const double p,const double tick) { return MathCeil(p/tick-1e-9)*tick; }
bool BVPFinitePositive(const double x) { return MathIsValidNumber(x) && x>0; }
#endif
