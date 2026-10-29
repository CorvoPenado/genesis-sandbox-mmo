/**
 * ============================================================================
 * PROVA DE CONCEITO 04: DOUBLE-CHECK LOCKING NA COLETA CONCORRENTE DE RECURSOS
 * Arquitetura: Validação Atômica de Estado em Memória Volátil (RAM)
 * Contexto: modules/systems/gathering.pwn
 * ============================================================================
 * 
 * PROBLEMA RESOLVIDO:
 * Em jogos multiplayer com ações temporizadas (ex.: barra de progresso de 5s para mineração),
 * dois ou mais jogadores podem iniciar a coleta do mesmo nó quase ao mesmo tempo.
 * Se o nó tiver apenas 1 unidade restante e a validação ocorrer apenas no início da ação,
 * ambos os jogadores receberão o drop ao término, gerando duplicação de itens (clonagem)
 * e nós com quantidade negativa de recursos no mundo.
 * 
 * SOLUÇÃO ARQUITETURAL:
 * Aplicação do padrão Double-Check Locking:
 * 1. Primeiro Check: Na detecção da tecla 'Y', valida se o nó está ativo e possui quantidade > 0.
 * 2. Segundo Check: No callback OnGatheringComplete (após os 5 segundos), revalida atomicamente
 *    o estado do nó na RAM antes de invocar GivePlayerItem e decrementar a entidade.
 */

#include <open.mp>

// Estados da sessão de coleta do jogador
static g_TargetNode[MAX_PLAYERS] = {-1, ...};
static g_GatherToolItem[MAX_PLAYERS] = {0, ...};
static g_GatherToolSlot[MAX_PLAYERS] = {-1, ...};

// ----------------------------------------------------------------------------
// 1. PRIMEIRO CHECK: INÍCIO DA AÇÃO TEMPORIZADA (AttemptToGather)
// ----------------------------------------------------------------------------
stock AttemptToGather(playerid) 
{
    // Localiza o nó mais próximo via indexação espacial O(1)
    new node_id = GetClosestActiveNode(playerid);
    if (node_id == -1) return 0; 

    // [CHECK 1]: Validação preliminar de existência e disponibilidade do recurso
    if (GetNodeType(node_id) == RES_TYPE_NONE || GetNodeAmount(node_id) <= 0) 
    {
        return SendClientMessage(playerid, 0xFF0000FF, "Este recurso esta esgotado.");
    }

    // Configuração de ferramenta e velocidade de extração
    new res_type = GetNodeType(node_id);
    new tool_slot = GetValidPlayerToolSlot(playerid, GetResourceToolType(res_type));
    new time_ms = CalculateGatherDuration(playerid, tool_slot);

    // Registra o alvo na sessão volátil do jogador
    g_TargetNode[playerid] = node_id;
    g_GatherToolItem[playerid] = (tool_slot != -1) ? PlayerInventory[playerid][tool_slot][invItemID] : 0;
    g_GatherToolSlot[playerid] = tool_slot;

    // Inicia a barra de progresso assíncrona (5 segundos) bloqueando controles e tocando animação
    StartProgressAction(playerid, time_ms, "OnGatheringComplete", false, 1187, "SWORD", "sword_4");
    return 1;
}

// ----------------------------------------------------------------------------
// 2. SEGUNDO CHECK: TÉRMINO DA AÇÃO (OnGatheringComplete)
// Invocado quando o timer de 5 segundos da barra de progresso é concluído
// ----------------------------------------------------------------------------
forward OnGatheringComplete(playerid);
public OnGatheringComplete(playerid) 
{
    new node_id = g_TargetNode[playerid];
    new used_tool_item = g_GatherToolItem[playerid];

    // Limpeza imediata da sessão para evitar reentrância
    g_TargetNode[playerid] = -1;
    g_GatherToolItem[playerid] = 0;
    g_GatherToolSlot[playerid] = -1;

    // Validação de sanidade do nó
    if (node_id == -1 || GetNodeType(node_id) == RES_TYPE_NONE) {
        return SendClientMessage(playerid, -1, "O recurso acabou antes de voce terminar.");
    }

    // ========================================================================
    // [CHECK 2]: DOUBLE-CHECK LOCKING ATÔMICO
    // Se outro jogador terminou a colheita milissegundos antes, o nó já terá
    // rnAmount == 0. A entrega é abortada imediatamente com zero clonagem.
    // ========================================================================
    if (GetNodeAmount(node_id) <= 0) 
    {
        return SendClientMessage(playerid, 0xFF0000FF, "Alguem coletou este recurso antes de voce.");
    }

    new res_type = GetNodeType(node_id);
    new prof_id = GetProficiencyID(res_type);
    new product_id = GetProductFromResource(res_type);
    new amount = GetGatheringYield(playerid, prof_id, 1, used_tool_item);

    // Crédito do item e decremento da quantidade atômica do nó
    if (GivePlayerItem(playerid, product_id, amount)) 
    {
        // Decrementa rnAmount na RAM e aciona respawn timer se rnAmount == 0
        HarvestResourceNode(node_id); 
        
        SendClientMessage(playerid, 0x00FF00FF, "Recurso coletado com sucesso!");

        // Se o nó ainda tiver unidades restantes, reencadeia automaticamente
        if (GetNodeAmount(node_id) > 0) {
            AttemptToGather(playerid);
        }
    }
    return 1;
}
