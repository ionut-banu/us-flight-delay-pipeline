{{
  config(
    materialized='table',
    partition_by={"field": "month_start", "data_type": "date"},
    cluster_by=["carrier_code"]
  )
}}

with base as (

    select *
    from {{ ref('int_flights_enriched') }}

)

select
    date_trunc(flight_date, month) as month_start,
    carrier_code,
    any_value(carrier_name) as carrier_name,

    count(*) as total_flights,
    sum(is_cancelled) as cancelled_flights,
    sum(is_diverted) as diverted_flights,
    countif(is_cancelled = 0) as non_cancelled_flights,

    sum(dep_delay_15_flag) as dep_delay_15_flights,
    sum(arr_delay_15_flag) as arr_delay_15_flights,
    sum(is_on_time_arrival) as on_time_arrival_flights,

    sum(coalesce(dep_delay_minutes, 0)) as sum_dep_delay_minutes,
    sum(coalesce(arr_delay_minutes, 0)) as sum_arr_delay_minutes,

    count(dep_delay_minutes) as dep_delay_rows,
    count(arr_delay_minutes) as arr_delay_rows

from base
group by 1, 2