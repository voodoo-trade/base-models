{{ config(
    materialized = 'incremental',
    incremental_strategy = 'delete+insert',
    unique_key = ['block_number','platform_name','platform_exchange_version'],
    cluster_by = ['block_timestamp::DATE'],
    tags = ['curated','reorg']
) }}

WITH nft_base_models AS (

    SELECT
        block_number,
        block_timestamp,
        tx_hash,
        event_index,
        event_type,
        platform_address,
        platform_name,
        platform_exchange_version,
        seller_address,
        buyer_address,
        nft_address,
        erc1155_value :: STRING AS erc1155_value,
        tokenId,
        currency_address,
        total_price_raw,
        total_fees_raw,
        platform_fee_raw,
        creator_fee_raw,
        tx_fee,
        origin_from_address,
        origin_to_address,
        origin_function_signature,
        input_data,
        nft_log_id,
        _log_id,
        _inserted_timestamp
    FROM
        {{ ref('silver__seaport_1_5_sales') }}

{% if is_incremental() %}
WHERE
    _inserted_timestamp >= (
        SELECT
            MAX(
                _inserted_timestamp
            ) - INTERVAL '36 hours'
        FROM
            {{ this }}
    )
{% endif %}
UNION ALL
SELECT
    block_number,
    block_timestamp,
    tx_hash,
    event_index,
    event_type,
    platform_address,
    platform_name,
    platform_exchange_version,
    seller_address,
    buyer_address,
    nft_address,
    erc1155_value :: STRING AS erc1155_value,
    tokenId,
    currency_address,
    total_price_raw,
    total_fees_raw,
    platform_fee_raw,
    creator_fee_raw,
    tx_fee,
    origin_from_address,
    origin_to_address,
    origin_function_signature,
    input_data,
    nft_log_id,
    _log_id,
    _inserted_timestamp
FROM
    {{ ref('silver__zeroex_sales') }}

{% if is_incremental() %}
WHERE
    _inserted_timestamp >= (
        SELECT
            MAX(
                _inserted_timestamp
            ) - INTERVAL '36 hours'
        FROM
            {{ this }}
    )
{% endif %}
),
prices_raw AS (
    SELECT
        HOUR,
        symbol,
        token_address,
        decimals,
        price AS hourly_prices
    FROM
        {{ ref('price__ez_hourly_token_prices') }}
    WHERE
        token_address IN (
            SELECT
                DISTINCT currency_address
            FROM
                nft_base_models
        )
        AND HOUR :: DATE IN (
            SELECT
                DISTINCT block_timestamp :: DATE
            FROM
                nft_base_models
        )
        AND token_address != '0x4200000000000000000000000000000000000006'
),
eth_price AS (
    SELECT
        HOUR,
        'ETH' AS symbol,
        'ETH' AS token_address,
        18 AS decimals,
        price AS eth_price_hourly
    FROM
        {{ ref('silver__hourly_prices_priority_eth') }}
    WHERE
        HOUR :: DATE IN (
            SELECT
                DISTINCT block_timestamp :: DATE
            FROM
                nft_base_models
        )
),
all_prices AS (
    SELECT
        HOUR,
        symbol,
        token_address,
        decimals,
        hourly_prices
    FROM
        prices_raw
    UNION ALL
    SELECT
        HOUR,
        symbol,
        token_address,
        decimals,
        eth_price_hourly
    FROM
        eth_price
    UNION ALL
    SELECT
        HOUR,
        'WETH' AS symbol,
        '0x4200000000000000000000000000000000000006' AS token_address,
        decimals,
        eth_price_hourly
    FROM
        eth_price
),
final_base AS (
    SELECT
        block_number,
        block_timestamp,
        tx_hash,
        event_index,
        event_type,
        platform_address,
        platform_name,
        platform_exchange_version,
        NULL AS aggregator_name,
        seller_address,
        buyer_address,
        nft_address,
        C.token_name AS project_name,
        erc1155_value,
        tokenId,
        p.symbol AS currency_symbol,
        currency_address,
        total_price_raw,
        total_fees_raw,
        platform_fee_raw,
        creator_fee_raw,
        CASE
            WHEN currency_address IN (
                'ETH',
                '0x4200000000000000000000000000000000000006'
            ) THEN total_price_raw / pow(
                10,
                18
            )
            ELSE COALESCE (total_price_raw / pow(10, p.decimals), total_price_raw)
        END AS price,
        IFF(
            p.decimals IS NULL,
            0,
            price * hourly_prices
        ) AS price_usd,
        CASE
            WHEN currency_address IN (
                'ETH',
                '0x4200000000000000000000000000000000000006'
            ) THEN total_fees_raw / pow(
                10,
                18
            )
            ELSE COALESCE (total_fees_raw / pow(10, p.decimals), total_fees_raw)
        END AS total_fees,
        IFF(
            p.decimals IS NULL,
            0,
            total_fees * hourly_prices
        ) AS total_fees_usd,
        CASE
            WHEN currency_address IN (
                'ETH',
                '0x4200000000000000000000000000000000000006'
            ) THEN platform_fee_raw / pow(
                10,
                18
            )
            ELSE COALESCE (platform_fee_raw / pow(10, p.decimals), platform_fee_raw)
        END AS platform_fee,
        IFF(
            p.decimals IS NULL,
            0,
            platform_fee * hourly_prices
        ) AS platform_fee_usd,
        CASE
            WHEN currency_address IN (
                'ETH',
                '0x4200000000000000000000000000000000000006'
            ) THEN creator_fee_raw / pow(
                10,
                18
            )
            ELSE COALESCE (creator_fee_raw / pow(10, p.decimals), creator_fee_raw)
        END AS creator_fee,
        IFF(
            p.decimals IS NULL,
            0,
            creator_fee * hourly_prices
        ) AS creator_fee_usd,
        tx_fee,
        tx_fee * eth_price_hourly AS tx_fee_usd,
        origin_from_address,
        origin_to_address,
        origin_function_signature,
        nft_log_id,
        input_data,
        _log_id,
        b._inserted_timestamp
    FROM
        nft_base_models b
        LEFT JOIN all_prices p
        ON DATE_TRUNC(
            'hour',
            b.block_timestamp
        ) = p.hour
        AND b.currency_address = p.token_address
        LEFT JOIN eth_price e
        ON DATE_TRUNC(
            'hour',
            b.block_timestamp
        ) = e.hour
        LEFT JOIN {{ ref('silver__contracts') }} C
        ON b.nft_address = C.contract_address
)

{% if is_incremental() %},
label_fill_sales AS (
    SELECT
        block_number,
        block_timestamp,
        tx_hash,
        event_index,
        event_type,
        platform_address,
        platform_name,
        platform_exchange_version,
        aggregator_name,
        seller_address,
        buyer_address,
        nft_address,
        C.token_name AS project_name,
        erc1155_value,
        tokenId,
        currency_symbol,
        currency_address,
        total_price_raw,
        total_fees_raw,
        platform_fee_raw,
        creator_fee_raw,
        price,
        price_usd,
        total_fees,
        total_fees_usd,
        platform_fee,
        platform_fee_usd,
        creator_fee,
        creator_fee_usd,
        tx_fee,
        tx_fee_usd,
        origin_from_address,
        origin_to_address,
        origin_function_signature,
        nft_log_id,
        input_data,
        _log_id,
        GREATEST(
            t._inserted_timestamp,
            C._inserted_timestamp
        ) AS _inserted_timestamp
    FROM
        {{ this }}
        t
        INNER JOIN {{ ref('silver__contracts') }} C
        ON t.nft_address = C.contract_address
    WHERE
        t.project_name IS NULL
        AND C.token_name IS NOT NULL
),
blocks_fill AS (
    SELECT
        * exclude (
            complete_nft_sales_id,
            inserted_timestamp,
            modified_timestamp,
            _invocation_id
        )
    FROM
        {{ this }}
    WHERE
        block_number IN (
            SELECT
                block_number
            FROM
                label_fill_sales
        )
        AND nft_log_id NOT IN (
            SELECT
                nft_log_id
            FROM
                label_fill_sales
        )
)
{% endif %},
final_joins AS (
    SELECT
        *
    FROM
        final_base

{% if is_incremental() %}
UNION ALL
SELECT
    *
FROM
    label_fill_sales
UNION ALL
SELECT
    *
FROM
    blocks_fill
{% endif %}
)
SELECT
    block_number,
    block_timestamp,
    tx_hash,
    event_index,
    event_type,
    platform_address,
    platform_name,
    platform_exchange_version,
    aggregator_name,
    seller_address,
    buyer_address,
    nft_address,
    project_name,
    erc1155_value,
    tokenId,
    currency_symbol,
    currency_address,
    total_price_raw,
    total_fees_raw,
    platform_fee_raw,
    creator_fee_raw,
    price,
    price_usd,
    total_fees,
    total_fees_usd,
    platform_fee,
    platform_fee_usd,
    creator_fee,
    creator_fee_usd,
    tx_fee,
    tx_fee_usd,
    origin_from_address,
    origin_to_address,
    origin_function_signature,
    nft_log_id,
    input_data,
    _log_id,
    _inserted_timestamp,
    {{ dbt_utils.generate_surrogate_key(
        ['tx_hash', 'event_index', 'nft_address','tokenId','platform_exchange_version']
    ) }} AS complete_nft_sales_id,
    SYSDATE() AS inserted_timestamp,
    SYSDATE() AS modified_timestamp,
    '{{ invocation_id }}' AS _invocation_id
FROM
    final_joins qualify(ROW_NUMBER() over(PARTITION BY nft_log_id
ORDER BY
    _inserted_timestamp DESC)) = 1
