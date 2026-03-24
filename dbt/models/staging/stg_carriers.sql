{{ config(materialized='view') }}

with source_data as (

    select *
    from {{ source('flights_raw', 'carriers') }}

),

cleaned as (

    select
        nullif(upper(trim(cast(code as string))), '') as carrier_code,
        nullif(trim(cast(description as string)), '') as carrier_name
    from source_data

)

select
    carrier_code,
    carrier_name
from cleaned
where carrier_code is not null