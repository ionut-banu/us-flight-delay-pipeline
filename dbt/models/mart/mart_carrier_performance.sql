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
    round(avg(dep_delay_minutes), 2) as avg_dep_delay_minutes,
    round(avg(arr_delay_minutes), 2) as avg_arr_delay_minutes,
    round(safe_divide(sum(dep_delay_15_flag), count(*)), 4) as dep_delay_15_rate,
    round(safe_divide(sum(arr_delay_15_flag), countif(is_cancelled = 0)), 4) as arr_delay_15_rate,
    round(safe_divide(sum(is_on_time_arrival), countif(is_cancelled = 0)), 4) as on_time_arrival_rate,
    round(safe_divide(sum(is_cancelled), count(*)), 4) as cancellation_rate
from base
group by 1, 2