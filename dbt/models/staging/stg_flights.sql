{{ config(materialized='view') }}

with source_data as (

    select
        _table_suffix as source_month_suffix,
        safe_cast(Year as int64) as flight_year,
        safe_cast(Quarter as int64) as flight_quarter,
        safe_cast(Month as int64) as flight_month,
        safe_cast(DayofMonth as int64) as day_of_month,
        safe_cast(DayOfWeek as int64) as day_of_week,
        cast(FlightDate as date) as flight_date,

        nullif(trim(cast(Reporting_Airline as string)), '') as carrier_code,
        safe_cast(DOT_ID_Reporting_Airline as int64) as dot_id_reporting_airline,
        nullif(trim(cast(IATA_CODE_Reporting_Airline as string)), '') as iata_code_reporting_airline,
        nullif(trim(cast(Tail_Number as string)), '') as tail_num,
        safe_cast(Flight_Number_Reporting_Airline as int64) as flight_number,

        safe_cast(OriginAirportID as int64) as origin_airport_id,
        safe_cast(OriginAirportSeqID as int64) as origin_airport_seq_id,
        safe_cast(OriginCityMarketID as int64) as origin_city_market_id,
        nullif(trim(cast(Origin as string)), '') as origin_airport_code,
        nullif(trim(cast(OriginCityName as string)), '') as origin_city_name,
        nullif(trim(cast(OriginState as string)), '') as origin_state_code,
        safe_cast(OriginStateFips as int64) as origin_state_fips,
        nullif(trim(cast(OriginStateName as string)), '') as origin_state_name,
        safe_cast(OriginWac as int64) as origin_wac,

        safe_cast(DestAirportID as int64) as dest_airport_id,
        safe_cast(DestAirportSeqID as int64) as dest_airport_seq_id,
        safe_cast(DestCityMarketID as int64) as dest_city_market_id,
        nullif(trim(cast(Dest as string)), '') as dest_airport_code,
        nullif(trim(cast(DestCityName as string)), '') as dest_city_name,
        nullif(trim(cast(DestState as string)), '') as dest_state_code,
        safe_cast(DestStateFips as int64) as dest_state_fips,
        nullif(trim(cast(DestStateName as string)), '') as dest_state_name,
        safe_cast(DestWac as int64) as dest_wac,

        safe_cast(CRSDepTime as int64) as crs_dep_time,
        safe_cast(DepTime as int64) as dep_time,
        safe_cast(DepDelay as float64) as dep_delay_minutes,
        safe_cast(DepDelayMinutes as float64) as dep_delay_minutes_non_negative,
        safe_cast(DepDel15 as int64) as dep_delay_15_flag,
        safe_cast(DepartureDelayGroups as int64) as departure_delay_group,
        nullif(trim(cast(DepTimeBlk as string)), '') as dep_time_block,
        safe_cast(TaxiOut as float64) as taxi_out_minutes,
        safe_cast(WheelsOff as int64) as wheels_off,
        safe_cast(WheelsOn as int64) as wheels_on,
        safe_cast(TaxiIn as float64) as taxi_in_minutes,
        safe_cast(CRSArrTime as int64) as crs_arr_time,
        safe_cast(ArrTime as int64) as arr_time,
        safe_cast(ArrDelay as float64) as arr_delay_minutes,
        safe_cast(ArrDelayMinutes as float64) as arr_delay_minutes_non_negative,
        safe_cast(ArrDel15 as int64) as arr_delay_15_flag,
        safe_cast(ArrivalDelayGroups as int64) as arrival_delay_group,
        nullif(trim(cast(ArrTimeBlk as string)), '') as arr_time_block,
        safe_cast(Cancelled as int64) as is_cancelled,
        nullif(trim(cast(CancellationCode as string)), '') as cancellation_code,
        safe_cast(Diverted as int64) as is_diverted,
        safe_cast(Distance as float64) as distance_miles

    from `{{ target.project }}.flights_raw.raw_flights_*`
    where regexp_contains(_table_suffix, r'^[0-9]{4}_(1[0-2]|[1-9])$')

),

final as (

    select
        concat(
            coalesce(cast(flight_date as string), ''), '|',
            coalesce(carrier_code, ''), '|',
            coalesce(cast(flight_number as string), ''), '|',
            coalesce(origin_airport_code, ''), '|',
            coalesce(dest_airport_code, '')
        ) as flight_key,
        source_month_suffix,
        flight_year,
        flight_quarter,
        flight_month,
        day_of_month,
        day_of_week,
        flight_date,
        format_date('%Y-%m', flight_date) as flight_year_month,

        carrier_code,
        dot_id_reporting_airline,
        iata_code_reporting_airline,
        tail_num,
        flight_number,

        origin_airport_id,
        origin_airport_seq_id,
        origin_city_market_id,
        origin_airport_code,
        origin_city_name,
        origin_state_code,
        origin_state_fips,
        origin_state_name,
        origin_wac,

        dest_airport_id,
        dest_airport_seq_id,
        dest_city_market_id,
        dest_airport_code,
        dest_city_name,
        dest_state_code,
        dest_state_fips,
        dest_state_name,
        dest_wac,

        crs_dep_time,
        dep_time,
        dep_delay_minutes,
        dep_delay_minutes_non_negative,
        coalesce(dep_delay_15_flag, case when dep_delay_minutes >= 15 then 1 else 0 end) as dep_delay_15_flag,
        departure_delay_group,
        dep_time_block,
        taxi_out_minutes,
        wheels_off,
        wheels_on,
        taxi_in_minutes,
        crs_arr_time,
        arr_time,
        arr_delay_minutes,
        arr_delay_minutes_non_negative,
        coalesce(arr_delay_15_flag, case when arr_delay_minutes >= 15 then 1 else 0 end) as arr_delay_15_flag,
        arrival_delay_group,
        arr_time_block,
        coalesce(is_cancelled, 0) as is_cancelled,
        cancellation_code,
        case
            when cancellation_code = 'A' then 'carrier'
            when cancellation_code = 'B' then 'weather'
            when cancellation_code = 'C' then 'nas'
            when cancellation_code = 'D' then 'security'
            else null
        end as cancellation_reason,
        coalesce(is_diverted, 0) as is_diverted,
        case
            when coalesce(is_cancelled, 0) = 1 then 0
            when coalesce(is_diverted, 0) = 1 then 0
            when coalesce(arr_delay_minutes, 0) <= 0 then 1
            else 0
        end as is_on_time_arrival,
        distance_miles

    from source_data

)

select *
from final
where flight_date is not null
  and carrier_code is not null
  and origin_airport_code is not null
  and dest_airport_code is not null