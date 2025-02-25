{{ config(
    materialized = 'incremental',
    unique_key = "contract_address",
    full_refresh = false,
    tags = ['non_realtime']
) }}

WITH base AS (

    SELECT
        contract_address
    FROM
        {{ ref('silver__relevant_abi_contracts') }}

{% if is_incremental() %}
EXCEPT
SELECT
    contract_address
FROM
    {{ this }}
WHERE
    abi_data :data :result :: STRING <> 'Max rate limit reached'
{% endif %}
LIMIT
    5
), all_contracts AS (
    SELECT
        contract_address
    FROM
        base
    UNION
    SELECT
        contract_address
    FROM
        {{ ref('_retry_abis') }}
),
row_nos AS (
    SELECT
        contract_address,
        ROW_NUMBER() over (
            ORDER BY
                contract_address
        ) AS row_no
    FROM
        all_contracts
),
batched AS ({% for item in range(15) %}
SELECT
    rn.contract_address, live.udf_api('GET', CONCAT('https://api.basescan.org/api?module=contract&action=getabi&address=', rn.contract_address, '&apikey={base_key}'),{ 'User-Agent': 'FlipsideStreamline' },{},'EXPLORER') AS abi_data, SYSDATE() AS _inserted_timestamp
FROM
    row_nos rn
WHERE
    row_no = {{ item }}

    {% if not loop.last %}
    UNION ALL
    {% endif %}
{% endfor %})
SELECT
    contract_address,
    abi_data,
    _inserted_timestamp
FROM
    batched
