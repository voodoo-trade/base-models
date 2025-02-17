{{ config(
    materialized = 'incremental',
    incremental_strategy = 'delete+insert',
    unique_key = "block_number",
    tags = ['curated']
) }}

WITH pool_creation AS (

    SELECT
        block_number,
        block_timestamp,
        tx_hash,
        event_index,
        contract_address,
        regexp_substr_all(SUBSTR(DATA, 3, len(DATA)), '.{64}') AS segmented_data,
        CONCAT('0x', SUBSTR(topics [1] :: STRING, 27, 40)) AS token0,
        CONCAT('0x', SUBSTR(topics [2] :: STRING, 27, 40)) AS token1,
        CONCAT('0x', SUBSTR(segmented_data [0] :: STRING, 25, 40)) AS pool_address,
        utils.udf_hex_to_int(
            segmented_data [1] :: STRING
        ) :: INT AS pool_id,
        _log_id,
        _inserted_timestamp
    FROM
        {{ ref ('silver__logs') }}
    WHERE
        contract_address = '0xfda619b6d20975be80a10332cd39b9a4b0faa8bb' --factory
        AND topics [0] :: STRING = '0x0d3648bd0f6ba80134a33ba9275ac585d9d315f0ad8355cddefde31afa28d0e9' --PairCreated

{% if is_incremental() %}
AND _inserted_timestamp >= (
    SELECT
        MAX(_inserted_timestamp) - INTERVAL '12 hours'
    FROM
        {{ this }}
)
AND pool_address NOT IN (
    SELECT
        DISTINCT pool_address
    FROM
        {{ this }}
)
{% endif %}
)
SELECT
    block_number,
    block_timestamp,
    tx_hash,
    event_index,
    contract_address,
    token0,
    token1,
    pool_address,
    pool_id,
    _log_id,
    _inserted_timestamp
FROM
    pool_creation
