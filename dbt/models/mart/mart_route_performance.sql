{{
  config(
    materialized='table',
    cluster_by=["origin_airport_code", "dest_airport_code"]
  )
}}

with base as (

    select *
    from {{ ref('int_flights_enriched') }}

)

select
    route_code,
    any_value(route_label) as route_label,
    origin_airport_code,
    any_value(coalesce(origin_airport_name, origin_city_name)) as origin_label,
    dest_airport_code,
    any_value(coalesce(dest_airport_name, dest_city_name)) as dest_label,
    count(*) as total_flights,
    count(distinct carrier_code) as carrier_count,
    round(avg(distance_miles), 2) as avg_distance_miles,
    round(avg(dep_delay_minutes), 2) as avg_dep_delay_minutes,
    round(avg(arr_delay_minutes), 2) as avg_arr_delay_minutes,
    round(safe_divide(sum(dep_delay_15_flag), count(*)), 4) as dep_delay_15_rate,
    round(safe_divide(sum(arr_delay_15_flag), countif(is_cancelled = 0)), 4) as arr_delay_15_rate,
    round(safe_divide(sum(is_cancelled), count(*)), 4) as cancellation_rate,
    round(safe_divide(sum(is_diverted), count(*)), 4) as diversion_rate
from base
group by 1, 3, 5