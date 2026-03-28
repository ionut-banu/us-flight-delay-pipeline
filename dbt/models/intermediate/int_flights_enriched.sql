{{ config(materialized='view') }}

with flights as (

    select *
    from {{ ref('stg_flights') }}

),

carriers as (

    select *
    from {{ ref('stg_carriers') }}

),

origin_airports as (

    select *
    from {{ ref('stg_airports') }}

),

dest_airports as (

    select *
    from {{ ref('stg_airports') }}

)

select
    f.*,
    c.carrier_name,
    oa.airport_name as origin_airport_name,
    oa.city_name as origin_airport_city,
    oa.state_code as origin_airport_state,
    da.airport_name as dest_airport_name,
    da.city_name as dest_airport_city,
    da.state_code as dest_airport_state,
    concat(f.origin_airport_code, '-', f.dest_airport_code) as route_code,
    concat(
        coalesce(oa.city_name, f.origin_city_name),
        ' -> ',
        coalesce(da.city_name, f.dest_city_name)
    ) as route_label
from flights f
left join carriers c
    on f.carrier_code = c.carrier_code
left join origin_airports oa
    on f.origin_airport_code = oa.airport_code
left join dest_airports da
    on f.dest_airport_code = da.airport_code