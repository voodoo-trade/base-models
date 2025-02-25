{{ config(
    materialized = 'incremental',
    incremental_strategy = 'delete+insert',
    unique_key = "block_number",
    cluster_by = ['block_timestamp::DATE', '_inserted_timestamp::DATE'],
    post_hook = "ALTER TABLE {{ this }} ADD SEARCH OPTIMIZATION on equality(contract_address, tx_hash)",
    tags = ['curated','reorg']
) }}

WITH base AS (

    SELECT
        _log_id,
        block_number,
        tx_hash,
        block_timestamp,
        event_index,
        contract_address,
        topics,
        DATA,
        regexp_substr_all(SUBSTR(DATA, 3, len(DATA)), '.{64}') AS segmented_data,
        TO_TIMESTAMP_NTZ(_inserted_timestamp) AS _inserted_timestamp
    FROM
        {{ ref('silver__logs') }}
    WHERE
        tx_status = 'SUCCESS'
        AND (
            (
                topics [0] :: STRING = '0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef'
                AND DATA = '0x'
                AND topics [3] IS NOT NULL
            ) --erc721s
            OR (
                topics [0] :: STRING = '0xc3d58168c5ae7397731d063d5bbf3d657854427343f4c083240f7aacaa2d0f62'
            ) --erc1155s
            OR (
                topics [0] :: STRING = '0x4a39dc06d4c0dbc64b70af90fd698a233a518aa5d07e595d983b8c0526c8f7fb'
            ) --erc1155s TransferBatch event
        )

{% if is_incremental() %}
AND TO_TIMESTAMP_NTZ(_inserted_timestamp) >= (
    SELECT
        MAX(_inserted_timestamp) - INTERVAL '24 hours'
    FROM
        {{ this }}
)
{% endif %}
),
erc721s AS (
    SELECT
        _log_id,
        block_number,
        tx_hash,
        block_timestamp,
        contract_address,
        CONCAT('0x', SUBSTR(topics [1] :: STRING, 27, 40)) AS from_address,
        CONCAT('0x', SUBSTR(topics [2] :: STRING, 27, 40)) AS to_address,
        utils.udf_hex_to_int(
            topics [3] :: STRING
        ) :: STRING AS token_id,
        NULL AS erc1155_value,
        TO_TIMESTAMP_NTZ(_inserted_timestamp) AS _inserted_timestamp,
        event_index
    FROM
        base
    WHERE
        topics [0] :: STRING = '0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef'
        AND DATA = '0x'
        AND topics [3] IS NOT NULL
),
transfer_singles AS (
    SELECT
        _log_id,
        block_number,
        tx_hash,
        block_timestamp,
        contract_address,
        CONCAT('0x', SUBSTR(topics [1] :: STRING, 27, 40)) AS operator_address,
        CONCAT('0x', SUBSTR(topics [2] :: STRING, 27, 40)) AS from_address,
        CONCAT('0x', SUBSTR(topics [3] :: STRING, 27, 40)) AS to_address,
        utils.udf_hex_to_int(
            segmented_data [0] :: STRING
        ) :: STRING AS token_id,
        utils.udf_hex_to_int(
            segmented_data [1] :: STRING
        ) :: STRING AS erc1155_value,
        TO_TIMESTAMP_NTZ(_inserted_timestamp) AS _inserted_timestamp,
        event_index
    FROM
        base
    WHERE
        topics [0] :: STRING = '0xc3d58168c5ae7397731d063d5bbf3d657854427343f4c083240f7aacaa2d0f62'
        AND to_address IS NOT NULL
),
transfer_batch_raw AS (
    SELECT
        block_number,
        block_timestamp,
        tx_hash,
        event_index,
        segmented_data,
        CONCAT('0x', SUBSTR(topics [1] :: STRING, 27, 40)) AS operator_address,
        CONCAT('0x', SUBSTR(topics [2] :: STRING, 27, 40)) AS from_address,
        CONCAT('0x', SUBSTR(topics [3] :: STRING, 27, 40)) AS to_address,
        contract_address,
        utils.udf_hex_to_int(
            segmented_data [2] :: STRING
        ) AS tokenid_length,
        tokenid_length AS quantity_length,
        _log_id,
        TO_TIMESTAMP_NTZ(_inserted_timestamp) AS _inserted_timestamp
    FROM
        base
    WHERE
        topics [0] :: STRING = '0x4a39dc06d4c0dbc64b70af90fd698a233a518aa5d07e595d983b8c0526c8f7fb'
        AND to_address IS NOT NULL
),
flattened AS (
    SELECT
        block_number,
        block_timestamp,
        _log_id,
        _inserted_timestamp,
        tx_hash,
        event_index,
        operator_address,
        from_address,
        to_address,
        contract_address,
        INDEX,
        VALUE,
        tokenid_length,
        quantity_length,
        2 + tokenid_length AS tokenid_indextag,
        4 + tokenid_length AS quantity_indextag_start,
        4 + tokenid_length + tokenid_length AS quantity_indextag_end,
        CASE
            WHEN INDEX BETWEEN 3
            AND (
                tokenid_indextag
            ) THEN 'tokenid'
            WHEN INDEX BETWEEN (
                quantity_indextag_start
            )
            AND (
                quantity_indextag_end
            ) THEN 'quantity'
            ELSE NULL
        END AS label
    FROM
        transfer_batch_raw,
        LATERAL FLATTEN (
            input => segmented_data
        )
),
tokenid_list AS (
    SELECT
        block_number,
        block_timestamp,
        _log_id,
        _inserted_timestamp,
        tx_hash,
        event_index,
        operator_address,
        from_address,
        to_address,
        contract_address,
        utils.udf_hex_to_int(
            VALUE :: STRING
        ) :: STRING AS tokenId,
        ROW_NUMBER() over (
            PARTITION BY tx_hash,
            event_index
            ORDER BY
                INDEX ASC
        ) AS tokenid_order
    FROM
        flattened
    WHERE
        label = 'tokenid'
),
quantity_list AS (
    SELECT
        tx_hash,
        event_index,
        utils.udf_hex_to_int(
            VALUE :: STRING
        ) :: STRING AS quantity,
        ROW_NUMBER() over (
            PARTITION BY tx_hash,
            event_index
            ORDER BY
                INDEX ASC
        ) AS quantity_order
    FROM
        flattened
    WHERE
        label = 'quantity'
),
transfer_batch_final AS (
    SELECT
        block_number,
        block_timestamp,
        _log_id,
        _inserted_timestamp,
        t.tx_hash,
        t.event_index,
        operator_address,
        from_address,
        to_address,
        contract_address,
        t.tokenId AS token_id,
        q.quantity AS erc1155_value,
        tokenid_order AS intra_event_index
    FROM
        tokenid_list t
        INNER JOIN quantity_list q
        ON t.tx_hash = q.tx_hash
        AND t.event_index = q.event_index
        AND t.tokenid_order = q.quantity_order
),
all_transfers AS (
    SELECT
        block_number,
        tx_hash,
        block_timestamp,
        contract_address,
        from_address,
        to_address,
        token_id,
        erc1155_value,
        _inserted_timestamp,
        event_index,
        1 AS intra_event_index,
        'erc721_Transfer' AS token_transfer_type,
        CONCAT(
            _log_id,
            '-',
            contract_address,
            '-',
            token_id
        ) AS _log_id
    FROM
        erc721s
    UNION ALL
    SELECT
        block_number,
        tx_hash,
        block_timestamp,
        contract_address,
        from_address,
        to_address,
        token_id,
        erc1155_value,
        _inserted_timestamp,
        event_index,
        1 AS intra_event_index,
        'erc1155_TransferSingle' AS token_transfer_type,
        CONCAT(
            _log_id,
            '-',
            contract_address,
            '-',
            token_id
        ) AS _log_id
    FROM
        transfer_singles
    WHERE
        erc1155_value != '0'
    UNION ALL
    SELECT
        block_number,
        tx_hash,
        block_timestamp,
        contract_address,
        from_address,
        to_address,
        token_id,
        erc1155_value,
        _inserted_timestamp,
        event_index,
        intra_event_index,
        'erc1155_TransferBatch' AS token_transfer_type,
        CONCAT(
            _log_id,
            '-',
            contract_address,
            '-',
            token_id,
            '-',
            intra_event_index
        ) AS _log_id
    FROM
        transfer_batch_final
    WHERE
        erc1155_value != '0'
),
transfer_base AS (
    SELECT
        block_number,
        block_timestamp,
        tx_hash,
        event_index,
        intra_event_index,
        contract_address,
        C.token_name AS project_name,
        from_address,
        to_address,
        A.token_id AS tokenId,
        erc1155_value,
        CASE
            WHEN from_address = '0x0000000000000000000000000000000000000000' THEN 'mint'
            ELSE 'other'
        END AS event_type,
        token_transfer_type,
        A._log_id,
        A._inserted_timestamp
    FROM
        all_transfers A
        LEFT JOIN {{ ref('silver__contracts') }} C USING (contract_address)
    WHERE
        to_address IS NOT NULL
)

{% if is_incremental() %},
fill_transfers AS (
    SELECT
        t.block_number,
        t.block_timestamp,
        t.tx_hash,
        t.event_index,
        t.intra_event_index,
        t.contract_address,
        C.token_name AS project_name,
        t.from_address,
        t.to_address,
        t.tokenId,
        t.erc1155_value,
        t.event_type,
        t.token_transfer_type,
        t._log_id,
        GREATEST(
            t._inserted_timestamp,
            C._inserted_timestamp
        ) AS _inserted_timestamp
    FROM
        {{ this }}
        t
        INNER JOIN {{ ref('silver__contracts') }} C USING (contract_address)
    WHERE
        t.project_name IS NULL
        AND C.token_name IS NOT NULL
),
blocks_fill AS (
    SELECT
        * exclude (
            nft_transfers_id,
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
                fill_transfers
        )
        AND _log_id NOT IN (
            SELECT
                _log_id
            FROM
                fill_transfers
        )
)
{% endif %},
final_base AS (
    SELECT
        block_number,
        block_timestamp,
        tx_hash,
        event_index,
        intra_event_index,
        contract_address,
        project_name,
        from_address,
        to_address,
        tokenId,
        erc1155_value,
        event_type,
        token_transfer_type,
        _log_id,
        _inserted_timestamp
    FROM
        transfer_base

{% if is_incremental() %}
UNION ALL
SELECT
    block_number,
    block_timestamp,
    tx_hash,
    event_index,
    intra_event_index,
    contract_address,
    project_name,
    from_address,
    to_address,
    tokenId,
    erc1155_value,
    event_type,
    token_transfer_type,
    _log_id,
    _inserted_timestamp
FROM
    fill_transfers
UNION ALL
SELECT
    block_number,
    block_timestamp,
    tx_hash,
    event_index,
    intra_event_index,
    contract_address,
    project_name,
    from_address,
    to_address,
    tokenId,
    erc1155_value,
    event_type,
    token_transfer_type,
    _log_id,
    _inserted_timestamp
FROM
    blocks_fill
{% endif %}
)
SELECT
    block_number,
    block_timestamp,
    tx_hash,
    event_index,
    intra_event_index,
    contract_address,
    project_name,
    from_address,
    to_address,
    tokenId,
    erc1155_value,
    event_type,
    token_transfer_type,
    _log_id,
    _inserted_timestamp,
    {{ dbt_utils.generate_surrogate_key(
        ['tx_hash','event_index','intra_event_index']
    ) }} AS nft_transfers_id,
    SYSDATE() AS inserted_timestamp,
    SYSDATE() AS modified_timestamp,
    '{{ invocation_id }}' AS _invocation_id
FROM
    final_base qualify ROW_NUMBER() over (
        PARTITION BY _log_id
        ORDER BY
            _inserted_timestamp DESC
    ) = 1
