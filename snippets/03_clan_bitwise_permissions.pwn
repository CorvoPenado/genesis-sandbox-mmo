/**
 * ============================================================================
 * PROVA DE CONCEITO 03: GOVERNANÇA DE CLÃS COM BITWISE FLAGS EM MEMÓRIA
 * Arquitetura: Sistema de Permissões Granulares por Operadores Bit a Bit
 * Contexto: modules/systems/clan_system.pwn
 * ============================================================================
 * 
 * PROBLEMA RESOLVIDO:
 * Gerenciar dezenas de permissões individuais por cargo ou membro (saque em baús,
 * movimentação bancária, gestão de salários, expulsão de membros) costuma gerar
 * estruturas pesadas em banco e alto consumo de memória RAM.
 * 
 * SOLUÇÃO ARQUITETURAL:
 * Mapeamento de 8 permissões granulares em um único inteiro de 32 bits através
 * de máscaras binárias (bitflags). A validação de acesso ocorre em tempo de CPU
 * insignificante através do operador bitwise AND (&).
 */

#include <open.mp>

// ----------------------------------------------------------------------------
// 1. DEFINIÇÃO DAS MÁSCARAS BINÁRIAS (BITFLAGS)
// ----------------------------------------------------------------------------
#define PERM_CHEST_ACCESS   1   // 0000 0001 (bit 0): Sacar do baú coletivo
#define PERM_CHEST_MANAGE   2   // 0000 0010 (bit 1): Gerenciar baús
#define PERM_BANK_WITHDRAW  4   // 0000 0100 (bit 2): Sacar do banco da guilda
#define PERM_INVITE         8   // 0000 1000 (bit 3): Convidar novos recrutas
#define PERM_KICK           16  // 0001 0000 (bit 4): Expulsar membros inferiores
#define PERM_PROMOTE        32  // 0010 0000 (bit 5): Promover/rebaixar patentes
#define PERM_ACCESS_MANAGE  64  // 0100 0000 (bit 6): Delegar permissões
#define PERM_SALARY         128 // 1000 0000 (bit 7): Configurar folha salarial

// Cargos pré-definidos do Clã
enum {
    CLAN_RANK_NONE = 0,
    CLAN_RANK_NOVATO = 1,
    CLAN_RANK_CADETE = 2,
    CLAN_RANK_SOLDADO = 3,
    CLAN_RANK_OFICIAL = 4,
    CLAN_RANK_LIDER = 5
};

// Sessão do jogador em memória (RAM)
static g_PlayerClan[MAX_PLAYERS];
static g_PlayerClanRank[MAX_PLAYERS];
static g_PlayerClanPerms[MAX_PLAYERS]; // Inteiro armazenando os bits ativos

// ----------------------------------------------------------------------------
// 2. FUNÇÃO DE VALIDAÇÃO BINÁRIA (CONTROLE DE ACESSO)
// ----------------------------------------------------------------------------

/**
 * Valida se o jogador possui a permissão requerida via teste de bitwise AND.
 * Líderes possuem bypass hierárquico implícito.
 */
stock bool:Clan_HasPermission(playerid, perm_flag)
{
    if (playerid < 0 || playerid >= MAX_PLAYERS || !IsPlayerConnected(playerid))
        return false;

    // Se o jogador não pertence a nenhum clã ativo
    if (g_PlayerClan[playerid] == 0)
        return false;

    // O Líder do clã possui bypass absoluto para todas as ações
    if (g_PlayerClanRank[playerid] == CLAN_RANK_LIDER)
        return true;

    // Teste Binário: Aplica a máscara de bits. Se o bit estiver ligado, resultado != 0
    return ((g_PlayerClanPerms[playerid] & perm_flag) != 0);
}

// ----------------------------------------------------------------------------
// 3. EXEMPLOS PRÁTICOS DE CONSUMO DE BITFLAGS NO DOMÍNIO
// ----------------------------------------------------------------------------

/**
 * Exemplo A: Verificação de acesso antes de abrir o cofre do Clã
 */
stock AttemptOpenClanVault(playerid, clan_id)
{
    if (g_PlayerClan[playerid] != clan_id) {
        return SendClientMessage(playerid, 0xFF6347FF, "[CLAN] Voce nao pertence a este cla.");
    }

    // Validação binária estrita para PERM_CHEST_ACCESS (Bit 0)
    if (!Clan_HasPermission(playerid, PERM_CHEST_ACCESS)) {
        return SendClientMessage(playerid, 0xFF6347FF, "[CLAN] Voce nao possui permissao para sacar itens deste bau.");
    }

    // Prossegue com o fluxo seguro de abertura do container
    return 1;
}

/**
 * Exemplo B: Modificação dinâmica de bits (Concessão, Revogação e Combinação)
 */
stock UpdateRankDefaults(rank)
{
    new default_flags = 0;

    switch (rank) {
        case CLAN_RANK_OFICIAL: {
            // Operador Bitwise OR (|): Combina múltiplas permissões em um único inteiro
            default_flags = (PERM_CHEST_ACCESS | PERM_BANK_WITHDRAW | PERM_INVITE | PERM_KICK | PERM_PROMOTE);
        }
        case CLAN_RANK_SOLDADO: {
            default_flags = (PERM_INVITE);
        }
    }
    return default_flags;
}

stock TogglePlayerClanPermission(playerid, perm_flag)
{
    // Operador Bitwise XOR (^): Inverte o estado de um bit específico (toggle liga/desliga)
    g_PlayerClanPerms[playerid] ^= perm_flag;
    return g_PlayerClanPerms[playerid];
}
