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

    sum(is_cancelled) as cancelled_flights,
    sum(is_diverted) as diverted_flights,
    countif(is_cancelled = 0) as non_cancelled_flights,

    sum(dep_delay_15_flag) as dep_delay_15_flights,
    sum(arr_delay_15_flag) as arr_delay_15_flights,
    sum(is_on_time_arrival) as on_time_arrival_flights,

    sum(coalesce(dep_delay_minutes, 0)) as sum_dep_delay_minutes,
    sum(coalesce(arr_delay_minutes, 0)) as sum_arr_delay_minutes,
    count(dep_delay_minutes) as dep_delay_rows,
    count(arr_delay_minutes) as arr_delay_rows,

    sum(coalesce(distance_miles, 0)) as sum_distance_miles,
    count(distance_miles) as distance_rows

from base
group by 1, 3, 5