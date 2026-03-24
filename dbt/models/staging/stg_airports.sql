{{ config(materialized='view') }}

with source_data as (

    select *
    from {{ source('flights_raw', 'airports') }}

),

cleaned as (

    select
        nullif(upper(trim(cast(code as string))), '') as airport_code,
        nullif(trim(cast(description as string)), '') as airport_description
    from source_data

)

select
    airport_code,
    airport_description,
    split(airport_description, ': ')[safe_offset(0)] as city_state,
    split(airport_description, ': ')[safe_offset(1)] as airport_name,
    split(split(airport_description, ': ')[safe_offset(0)], ', ')[safe_offset(0)] as city_name,
    split(split(airport_description, ': ')[safe_offset(0)], ', ')[safe_offset(1)] as state_code
from cleaned
where airport_code is not null