/**
 * ============================================================================
 * PROVA DE CONCEITO 02: INDEXAÇÃO ESPACIAL EM TEMPO CONSTANTE O(1) VIA C++ R-TREE
 * Arquitetura: Particionamento Espacial Nativo com Streamer Plugin (Incognito)
 * Contexto: modules/systems/resources.pwn
 * ============================================================================
 * 
 * PROBLEMA RESOLVIDO:
 * No modelo legado, ao apertar a tecla de interação 'Y', o servidor executava um
 * laço iterativo de 0 a 1000 calculando distâncias euclidianas tridimensionais
 * via VectorSize(dx, dy, dz) na máquina virtual AMX (single-threaded).
 * 
 * SOLUÇÃO ARQUITETURAL:
 * Delegação do particionamento geométrico para a estrutura de dados R-Tree em C++
 * do Streamer Plugin. O ID do nó é indexado em um cilindro 3D via E_STREAMER_EXTRA_ID.
 * A busca passa a consultar apenas os volumes onde o jogador já está inserido,
 * reduzindo a complexidade de busca de O(N) para O(1).
 */

#include <open.mp>
#include <streamer>

#define MAX_NODE_CAPACITY   1000

enum E_RESOURCE_NODE {
    rnType,
    rnMaxAmount,
    rnAmount,
    rnObject,
    rnArea,                 // ID da área dinâmica no Streamer Plugin (C++)
    Float:rnX,
    Float:rnY,
    Float:rnZ,
    bool:rnActive
};

new ResourceNodes[MAX_NODE_CAPACITY][E_RESOURCE_NODE];

// ----------------------------------------------------------------------------
// 1. REGISTRO ESPACIAL NA ÁRVORE R DURANTE O SPAWN DO NÓ
// ----------------------------------------------------------------------------
stock RegisterNodeSpatialIndex(slot, Float:x, Float:y, Float:z, vw = 0, interior = 0)
{
    // Cria um cilindro 3D de detecção no espaço com raio de 3.0 metros
    ResourceNodes[slot][rnArea] = CreateDynamicCylinder(
        x, y, 
        z - 2.0, z + 3.0,   // Delimitação vertical (MinZ e MaxZ)
        3.0,                // Raio horizontal
        vw, interior, -1
    );

    // Mapeamento bidirecional nativo em C++: associa o índice do array à área
    Streamer_SetIntData(
        STREAMER_TYPE_AREA, 
        ResourceNodes[slot][rnArea], 
        E_STREAMER_EXTRA_ID, 
        slot
    );

    return 1;
}

// ----------------------------------------------------------------------------
// 2. CONSULTA ESPACIAL O(1) SEM LAÇO ITERATIVO NA VM AMX
// Invocado quando o jogador aciona a tecla de coleta 'Y'
// ----------------------------------------------------------------------------
stock GetClosestActiveNode(playerid, Float:range = 3.0) 
{
    #pragma unused range
    new areas[16];

    // O(1): Consulta nativa à R-Tree em C++. Retorna apenas as áreas onde o jogador está dentro.
    // Se o jogador não estiver em nenhuma área de recurso, retorna 0 instantaneamente.
    new count = GetPlayerDynamicAreas(playerid, areas, sizeof(areas));
    if (count <= 0) return -1;

    new best_id = -1;
    new Float:min_dist = 9999.0;
    new Float:px, Float:py, Float:pz;
    new bool:pos_cached = false;

    // Itera estritamente sobre a quantidade minúscula de áreas sobrepostas (geralmente 1)
    for (new i = 0; i < count; i++) 
    {
        // Resgate instantâneo do índice do nó mapeado no C++
        new node_id = Streamer_GetIntData(STREAMER_TYPE_AREA, areas[i], E_STREAMER_EXTRA_ID);

        if (node_id >= 0 && node_id < MAX_NODE_CAPACITY) 
        {
            // Valida se a área consultada pertence de fato ao nó e se ele possui recurso
            if (ResourceNodes[node_id][rnArea] == areas[i] && 
                ResourceNodes[node_id][rnActive] && 
                ResourceNodes[node_id][rnAmount] > 0 &&
                ResourceNodes[node_id][rnObject] != INVALID_OBJECT_ID) 
            {
                // Caminho rápido ideal: Se está em exatamente 1 área de recurso, retorna em O(1) imediato
                if (count == 1) {
                    return node_id;
                }

                // Desempate pontual estritamente se houver sobreposição rara de nós candidatos
                if (!pos_cached) {
                    GetPlayerPos(playerid, px, py, pz);
                    pos_cached = true;
                }

                new Float:dist = VectorSize(
                    px - ResourceNodes[node_id][rnX], 
                    py - ResourceNodes[node_id][rnY], 
                    pz - ResourceNodes[node_id][rnZ]
                );

                if (dist < min_dist) {
                    min_dist = dist;
                    best_id = node_id;
                }
            }
        }
    }
    return best_id;
}
