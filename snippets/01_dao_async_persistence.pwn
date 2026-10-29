/**
 * ============================================================================
 * PROVA DE CONCEITO 01: CAMADA DAO & PERSISTÊNCIA ASSÍNCRONA SEM RACE CONDITIONS
 * Arquitetura: Data Access Object (DAO) Pattern com a_mysql / open.mp
 * Contexto: modules/database/dao.pwn & modules/systems/vehicle_recovery.pwn
 * ============================================================================
 * 
 * PROBLEMA RESOLVIDO:
 * 1. Prevenção de Rollback: Em vez de salvar dados apenas no logout ou em timers
 *    periódicos, transições de estado críticas disparam persistência imediata.
 * 2. Eliminação de Race Condition ("Chave Fantasma"): Disparar um DELETE assíncrono
 *    e um INSERT imediatamente na linha seguinte no MySQL causa condição de corrida,
 *    onde o DELETE pode processar depois do INSERT, apagando a chave recém-criada.
 *    A solução impõe barreira causal via callback assíncrono estrito.
 */

#include <open.mp>
#include <a_mysql>

// Handler global da conexão com o banco de dados
extern MySQL:g_SQL;

// ----------------------------------------------------------------------------
// 1. PERSISTÊNCIA REATIVA IMEDIATA (ANTI-ROLLBACK VEICULAR)
// Invocado no momento exato em que o jogador desembarca (PLAYER_STATE_ONFOOT)
// ----------------------------------------------------------------------------
stock DAO_SaveVehicleState(vehicleid) 
{
    // Validação estrita de existência da entidade e registro primário no banco
    if (vehicleid == INVALID_VEHICLE_ID || VehicleInfo[vehicleid][vDbID] == 0) 
        return 0;

    new Float:x, Float:y, Float:z, Float:a, Float:hp;
    GetVehiclePos(vehicleid, x, y, z);
    GetVehicleZAngle(vehicleid, a);
    GetVehicleHealth(vehicleid, hp);

    new query[256];
    
    // Formatação segura (prevenção nativa de SQL Injection)
    mysql_format(g_SQL, query, sizeof(query), 
        "UPDATE player_vehicles SET pos_x=%f, pos_y=%f, pos_z=%f, pos_a=%f, health=%f, fuel=%f WHERE id=%d",
        x, y, z, a, hp, VehicleInfo[vehicleid][vFuel], VehicleInfo[vehicleid][vDbID]
    );

    // Despacho assíncrono não-bloqueante para a thread pool do driver C++
    mysql_tquery(g_SQL, query, "", "");
    return 1;
}

// ----------------------------------------------------------------------------
// 2. ELIMINAÇÃO DE RACE CONDITION: EXCLUSÃO E ENTREGA SEQUENCIAL DE CHAVES
// ----------------------------------------------------------------------------

/**
 * Passo 1: Solicita a exclusão atômica de chaves antigas de um veículo no banco.
 * Em vez de criar a nova chave imediatamente, aguardamos a confirmação do MySQL.
 */
stock DAO_DeleteVehicleKeys(veh_db_id, playerid = INVALID_PLAYER_ID) 
{
    new query[128];
    mysql_format(g_SQL, query, sizeof(query), 
        "DELETE FROM player_items WHERE item_id = %d AND durability = %d", 
        ITEM_CHAVE_VEICULO, veh_db_id
    );

    printf("[DAO] Solicitando exclusao de chaves do veiculo DB ID %d no banco...", veh_db_id);

    // Encaminha veh_db_id e playerid como argumentos para o callback assíncrono
    mysql_tquery(g_SQL, query, "DAO_OnVehicleKeysDeleted", "dd", veh_db_id, playerid);
    return 1;
}

/**
 * Passo 2: Callback de retorno invocado pela worker thread do MySQL quando
 * o DELETE foi efetivamente concluído em disco.
 */
forward DAO_OnVehicleKeysDeleted(veh_db_id, playerid);
public DAO_OnVehicleKeysDeleted(veh_db_id, playerid) 
{
    // Inspeciona os metadados da transação concluída
    new rows = cache_affected_rows();
    printf("[DAO] Chaves antigas do veiculo DB ID %d excluidas (%d registros afetados).", veh_db_id, rows);

    // BARREIRA DE SINCRONIZAÇÃO CAUSAL:
    // A nova chave só é emitida após termos certeza matemática de que as antigas foram deletadas
    if (playerid != INVALID_PLAYER_ID && IsPlayerConnected(playerid)) 
    {
        // Notifica o módulo consumidor de regras de negócio para entregar a NOVA chave
        CallLocalFunction("OnVehicleKeysDeletedComplete", "dd", playerid, veh_db_id);
    }
    return 1;
}
