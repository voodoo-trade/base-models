{{ config(
  materialized = 'incremental',
  incremental_strategy = 'delete+insert',
  unique_key = ['block_number','platform','version'],
  cluster_by = ['block_timestamp::DATE'],
  tags = ['curated','reorg']
) }}

WITH contracts AS (

  SELECT
    contract_address AS address,
    token_symbol AS symbol,
    token_decimals AS decimals,
    _inserted_timestamp
  FROM
    {{ ref('silver__contracts') }}
),
curve AS (
  SELECT
    block_number,
    block_timestamp,
    tx_hash,
    deployer_address AS contract_address,
    pool_address,
    pool_name,
    'curve' AS platform,
    'v1' AS version,
    _call_id AS _id,
    _inserted_timestamp,
    MAX(
      CASE
        WHEN token_num = 1 THEN token_address
      END
    ) AS token0,
    MAX(
      CASE
        WHEN token_num = 2 THEN token_address
      END
    ) AS token1,
    MAX(
      CASE
        WHEN token_num = 3 THEN token_address
      END
    ) AS token2,
    MAX(
      CASE
        WHEN token_num = 4 THEN token_address
      END
    ) AS token3,
    MAX(
      CASE
        WHEN token_num = 5 THEN token_address
      END
    ) AS token4,
    MAX(
      CASE
        WHEN token_num = 6 THEN token_address
      END
    ) AS token5,
    MAX(
      CASE
        WHEN token_num = 7 THEN token_address
      END
    ) AS token6,
    MAX(
      CASE
        WHEN token_num = 8 THEN token_address
      END
    ) AS token7
  FROM
    {{ ref('silver_dex__curve_pools') }}

{% if is_incremental() %}
WHERE
  _inserted_timestamp >= (
    SELECT
      MAX(_inserted_timestamp) - INTERVAL '12 hours'
    FROM
      {{ this }}
  )
{% endif %}
GROUP BY
  ALL
),
balancer AS (
  SELECT
    block_number,
    block_timestamp,
    tx_hash,
    contract_address,
    pool_address,
    pool_name,
    'balancer' AS platform,
    'v1' AS version,
    _log_id AS _id,
    _inserted_timestamp,
    token0,
    token1,
    token2,
    token3,
    token4,
    token5,
    token6,
    token7
  FROM
    {{ ref('silver_dex__balancer_pools') }}

{% if is_incremental() %}
WHERE
  _inserted_timestamp >= (
    SELECT
      MAX(_inserted_timestamp) - INTERVAL '12 hours'
    FROM
      {{ this }}
  )
{% endif %}
),
uni_v3 AS (
  SELECT
    block_number,
    block_timestamp,
    tx_hash,
    contract_address,
    pool_address,
    fee,
    tick_spacing,
    token0_address AS token0,
    token1_address AS token1,
    'uniswap-v3' AS platform,
    'v3' AS version,
    _id,
    _inserted_timestamp
  FROM
    {{ ref('silver_dex__univ3_pools') }}

{% if is_incremental() %}
WHERE
  _inserted_timestamp >= (
    SELECT
      MAX(_inserted_timestamp) - INTERVAL '12 hours'
    FROM
      {{ this }}
  )
{% endif %}
),
dackieswap AS (
  SELECT
    block_number,
    block_timestamp,
    tx_hash,
    contract_address,
    pool_address,
    fee,
    tick_spacing,
    token0_address AS token0,
    token1_address AS token1,
    'dackieswap' AS platform,
    'v1' AS version,
    _id,
    _inserted_timestamp
  FROM
    {{ ref('silver_dex__dackie_pools') }}

{% if is_incremental() %}
WHERE
  _inserted_timestamp >= (
    SELECT
      MAX(_inserted_timestamp) - INTERVAL '12 hours'
    FROM
      {{ this }}
  )
{% endif %}
),
sushi AS (
  SELECT
    block_number,
    block_timestamp,
    tx_hash,
    contract_address,
    pool_address,
    fee,
    tick_spacing,
    token0_address AS token0,
    token1_address AS token1,
    'sushiswap' AS platform,
    'v1' AS version,
    _id,
    _inserted_timestamp
  FROM
    {{ ref('silver_dex__sushi_pools') }}

{% if is_incremental() %}
WHERE
  _inserted_timestamp >= (
    SELECT
      MAX(_inserted_timestamp) - INTERVAL '12 hours'
    FROM
      {{ this }}
  )
{% endif %}
),
maverick AS (
  SELECT
    block_number,
    block_timestamp,
    tx_hash,
    contract_address,
    pool_address,
    NULL AS pool_name,
    tokenA AS token0,
    tokenB AS token1,
    'maverick' AS platform,
    'v1' AS version,
    _log_id AS _id,
    _inserted_timestamp
  FROM
    {{ ref('silver_dex__maverick_pools') }}

{% if is_incremental() %}
WHERE
  _inserted_timestamp >= (
    SELECT
      MAX(_inserted_timestamp) - INTERVAL '12 hours'
    FROM
      {{ this }}
  )
{% endif %}
),
swapbased AS (
  SELECT
    block_number,
    block_timestamp,
    tx_hash,
    contract_address,
    pool_address,
    NULL AS pool_name,
    token0,
    token1,
    'swapbased' AS platform,
    'v1' AS version,
    _log_id AS _id,
    _inserted_timestamp
  FROM
    {{ ref('silver_dex__swapbased_pools') }}

{% if is_incremental() %}
WHERE
  _inserted_timestamp >= (
    SELECT
      MAX(_inserted_timestamp) - INTERVAL '12 hours'
    FROM
      {{ this }}
  )
{% endif %}
),
aerodrome AS (
  SELECT
    block_number,
    block_timestamp,
    tx_hash,
    contract_address,
    pool_address,
    NULL AS pool_name,
    token0,
    token1,
    'aerodrome' AS platform,
    'v1' AS version,
    _log_id AS _id,
    _inserted_timestamp
  FROM
    {{ ref('silver_dex__aerodrome_pools') }}

{% if is_incremental() %}
WHERE
  _inserted_timestamp >= (
    SELECT
      MAX(_inserted_timestamp) - INTERVAL '12 hours'
    FROM
      {{ this }}
  )
{% endif %}
),
baseswap AS (
  SELECT
    block_number,
    block_timestamp,
    tx_hash,
    contract_address,
    pool_address,
    NULL AS pool_name,
    token0,
    token1,
    'baseswap' AS platform,
    'v1' AS version,
    _log_id AS _id,
    _inserted_timestamp
  FROM
    {{ ref('silver_dex__baseswap_pools') }}

{% if is_incremental() %}
WHERE
  _inserted_timestamp >= (
    SELECT
      MAX(_inserted_timestamp) - INTERVAL '12 hours'
    FROM
      {{ this }}
  )
{% endif %}
),
all_pools_standard AS (
  SELECT
    *
  FROM
    baseswap
  UNION ALL
  SELECT
    *
  FROM
    swapbased
  UNION ALL
  SELECT
    *
  FROM
    maverick
  UNION ALL
  SELECT
    *
  FROM
    aerodrome
),
all_pools_v3 AS (
  SELECT
    *
  FROM
    uni_v3
  UNION ALL
  SELECT
    *
  FROM
    sushi
  UNION ALL
  SELECT
    *
  FROM
    dackieswap
),
all_pools_other AS (
  SELECT
    *
  FROM
    balancer
  UNION ALL
  SELECT
    *
  FROM
    curve
),
FINAL AS (
  SELECT
    block_number,
    block_timestamp,
    tx_hash,
    contract_address,
    pool_address,
    CASE
      WHEN pool_name IS NULL THEN CONCAT(
        COALESCE(
          c0.symbol,
          CONCAT(SUBSTRING(token0, 1, 5), '...', SUBSTRING(token0, 39, 42))
        ),
        '-',
        COALESCE(
          c1.symbol,
          CONCAT(SUBSTRING(token1, 1, 5), '...', SUBSTRING(token1, 39, 42))
        )
      )
      ELSE pool_name
    END AS pool_name,
    OBJECT_CONSTRUCT(
      'token0',
      token0,
      'token1',
      token1
    ) AS tokens,
    OBJECT_CONSTRUCT(
      'token0',
      c0.symbol,
      'token1',
      c1.symbol
    ) AS symbols,
    OBJECT_CONSTRUCT(
      'token0',
      c0.decimals,
      'token1',
      c1.decimals
    ) AS decimals,
    platform,
    version,
    _id,
    p._inserted_timestamp
  FROM
    all_pools_standard p
    LEFT JOIN contracts c0
    ON c0.address = p.token0
    LEFT JOIN contracts c1
    ON c1.address = p.token1
  UNION ALL
  SELECT
    block_number,
    block_timestamp,
    tx_hash,
    contract_address,
    pool_address,
    CASE
      WHEN platform = 'uniswap-v3' THEN CONCAT(
        COALESCE(
          c0.symbol,
          CONCAT(SUBSTRING(token0, 1, 5), '...', SUBSTRING(token0, 39, 42))
        ),
        '-',
        COALESCE(
          c1.symbol,
          CONCAT(SUBSTRING(token1, 1, 5), '...', SUBSTRING(token1, 39, 42))
        ),
        ' ',
        COALESCE(
          fee,
          0
        ),
        ' ',
        COALESCE(
          tick_spacing,
          0
        ),
        ' UNI-V3 LP'
      )
      WHEN platform = 'sushiswap' THEN CONCAT(
        COALESCE(
          c0.symbol,
          CONCAT(SUBSTRING(token0, 1, 5), '...', SUBSTRING(token0, 39, 42))
        ),
        '-',
        COALESCE(
          c1.symbol,
          CONCAT(SUBSTRING(token1, 1, 5), '...', SUBSTRING(token1, 39, 42))
        ),
        ' ',
        COALESCE(
          fee,
          0
        ),
        ' ',
        COALESCE(
          tick_spacing,
          0
        ),
        ' SLP'
      )
      WHEN platform = 'dackieswap' THEN CONCAT(
        COALESCE(
          c0.symbol,
          CONCAT(SUBSTRING(token0, 1, 5), '...', SUBSTRING(token0, 39, 42))
        ),
        '-',
        COALESCE(
          c1.symbol,
          CONCAT(SUBSTRING(token1, 1, 5), '...', SUBSTRING(token1, 39, 42))
        ),
        ' ',
        COALESCE(
          fee,
          0
        ),
        ' ',
        COALESCE(
          tick_spacing,
          0
        ),
        ' DLP'
      )
    END AS pool_name,
    OBJECT_CONSTRUCT(
      'token0',
      token0,
      'token1',
      token1
    ) AS tokens,
    OBJECT_CONSTRUCT(
      'token0',
      c0.symbol,
      'token1',
      c1.symbol
    ) AS symbols,
    OBJECT_CONSTRUCT(
      'token0',
      c0.decimals,
      'token1',
      c1.decimals
    ) AS decimals,
    platform,
    version,
    _id,
    p._inserted_timestamp
  FROM
    all_pools_v3 p
    LEFT JOIN contracts c0
    ON c0.address = p.token0
    LEFT JOIN contracts c1
    ON c1.address = p.token1
  UNION ALL
  SELECT
    block_number,
    block_timestamp,
    tx_hash,
    contract_address,
    pool_address,
    CASE
      WHEN pool_name IS NULL THEN CONCAT(
        COALESCE(c0.symbol, SUBSTRING(token0, 1, 5) || '...' || SUBSTRING(token0, 39, 42)),
        CASE
          WHEN token1 IS NOT NULL THEN '-' || COALESCE(c1.symbol, SUBSTRING(token1, 1, 5) || '...' || SUBSTRING(token1, 39, 42))
          ELSE ''
        END,
        CASE
          WHEN token2 IS NOT NULL THEN '-' || COALESCE(c2.symbol, SUBSTRING(token2, 1, 5) || '...' || SUBSTRING(token2, 39, 42))
          ELSE ''
        END,
        CASE
          WHEN token3 IS NOT NULL THEN '-' || COALESCE(c3.symbol, SUBSTRING(token3, 1, 5) || '...' || SUBSTRING(token3, 39, 42))
          ELSE ''
        END,
        CASE
          WHEN token4 IS NOT NULL THEN '-' || COALESCE(c4.symbol, SUBSTRING(token4, 1, 5) || '...' || SUBSTRING(token4, 39, 42))
          ELSE ''
        END,
        CASE
          WHEN token5 IS NOT NULL THEN '-' || COALESCE(c5.symbol, SUBSTRING(token5, 1, 5) || '...' || SUBSTRING(token5, 39, 42))
          ELSE ''
        END,
        CASE
          WHEN token6 IS NOT NULL THEN '-' || COALESCE(c6.symbol, SUBSTRING(token6, 1, 5) || '...' || SUBSTRING(token6, 39, 42))
          ELSE ''
        END,
        CASE
          WHEN token7 IS NOT NULL THEN '-' || COALESCE(c7.symbol, SUBSTRING(token7, 1, 5) || '...' || SUBSTRING(token7, 39, 42))
          ELSE ''
        END
      )
      ELSE pool_name
    END AS pool_name,
    OBJECT_CONSTRUCT(
      'token0',
      token0,
      'token1',
      token1,
      'token2',
      token2,
      'token3',
      token3,
      'token4',
      token4,
      'token5',
      token5,
      'token6',
      token6,
      'token7',
      token7
    ) AS tokens,
    OBJECT_CONSTRUCT(
      'token0',
      c0.symbol,
      'token1',
      c1.symbol,
      'token2',
      c2.symbol,
      'token3',
      c3.symbol,
      'token4',
      c4.symbol,
      'token5',
      c5.symbol,
      'token6',
      c6.symbol,
      'token7',
      c7.symbol
    ) AS symbols,
    OBJECT_CONSTRUCT(
      'token0',
      c0.decimals,
      'token1',
      c1.decimals,
      'token2',
      c2.decimals,
      'token3',
      c3.decimals,
      'token4',
      c4.decimals,
      'token5',
      c5.decimals,
      'token6',
      c6.decimals,
      'token7',
      c7.decimals
    ) AS decimals,
    platform,
    version,
    _id,
    p._inserted_timestamp
  FROM
    all_pools_other p
    LEFT JOIN contracts c0
    ON c0.address = p.token0
    LEFT JOIN contracts c1
    ON c1.address = p.token1
    LEFT JOIN contracts c2
    ON c2.address = p.token2
    LEFT JOIN contracts c3
    ON c3.address = p.token3
    LEFT JOIN contracts c4
    ON c4.address = p.token4
    LEFT JOIN contracts c5
    ON c5.address = p.token5
    LEFT JOIN contracts c6
    ON c6.address = p.token6
    LEFT JOIN contracts c7
    ON c7.address = p.token7
)
SELECT
  block_number,
  block_timestamp,
  tx_hash,
  platform,
  version,
  contract_address,
  pool_address,
  pool_name,
  tokens,
  symbols,
  decimals,
  _id,
  _inserted_timestamp,
  {{ dbt_utils.generate_surrogate_key(
    ['pool_address']
  ) }} AS complete_dex_liquidity_pools_id,
  SYSDATE() AS inserted_timestamp,
  SYSDATE() AS modified_timestamp,
  '{{ invocation_id }}' AS _invocation_id
FROM
  FINAL
