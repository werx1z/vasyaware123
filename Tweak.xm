// Tweak.xm
#import <substrate.h>
#import <mach-o/dyld.h>
#import <UIKit/UIKit.h>
#import <math.h>

// ============ СТРУКТУРЫ ============
struct Vector3 { float x, y, z; };
struct Il2CppList { void* klass; void* monitor; void* items; int size; };

// ============ ОФФСЕТЫ ============
#define GET_LOCAL_PLAYER_RVA        0x5d6fe78
#define GET_PLAYER_LIST_OTHERS_RVA  0x5d701ec
#define SET_GUN_TARGET_POINT_RVA    0x3d8984c
#define SET_TARGET_LOOK_POINT_RVA   0x3d8995c

// Поля CharacterMotor
#define MY_TEAM_OFFSET               0xF4
#define RECIVED_PLAYER_POS_OFFSET    0x190
#define TARGET_AND_LOOK_POINT_OFFSET 0x218

// ============ НАСТРОЙКИ ============
static bool silentAimEnabled = true;
static bool useLookPointHook = false;
static float silentAimMaxDist = 300.0f;

// ============ БАЗА ============
static uintptr_t unityBase = 0;

static uintptr_t get_unity_base() {
    for (int i = 0; i < _dyld_image_count(); i++) {
        if (strstr(_dyld_get_image_name(i), "UnityFramework"))
            return (uintptr_t)_dyld_get_image_header(i);
    }
    return 0;
}

// ============ ФУНКЦИИ ИГРЫ ============
static void* (*get_LocalPlayer)() = NULL;
static void* (*get_PlayerListOthers)() = NULL;

// ============ ХЕЛПЕРЫ ============
static struct Vector3 read_vector3(void* base, uintptr_t off) {
    return *(struct Vector3*)((uint8_t*)base + off);
}
static int read_int(void* base, uintptr_t off) {
    return *(int*)((uint8_t*)base + off);
}
static float vec_dist(struct Vector3 a, struct Vector3 b) {
    float dx = a.x-b.x, dy = a.y-b.y, dz = a.z-b.z;
    return sqrtf(dx*dx + dy*dy + dz*dz);
}

// ============ ПОИСК БЛИЖАЙШЕГО ВРАГА ============
static void* find_closest_enemy(void* localPlayer, struct Vector3* outPos) {
    if (!localPlayer || !get_PlayerListOthers) return NULL;

    int myTeam = read_int(localPlayer, MY_TEAM_OFFSET);
    struct Vector3 myPos = read_vector3(localPlayer, RECIVED_PLAYER_POS_OFFSET);

    struct Il2CppList* list = (struct Il2CppList*)get_PlayerListOthers();
    if (!list || list->size <= 0) return NULL;

    void** items = (void**)list->items;
    void* best = NULL;
    float bestDist = silentAimMaxDist;

    for (int i = 0; i < list->size; i++) {
        void* p = items[i];
        if (!p || p == localPlayer) continue;
        if (read_int(p, MY_TEAM_OFFSET) == myTeam) continue;

        struct Vector3 ePos = read_vector3(p, RECIVED_PLAYER_POS_OFFSET);
        if (ePos.x == 0 && ePos.y == 0 && ePos.z == 0) continue;

        float d = vec_dist(myPos, ePos);
        if (d < bestDist) { bestDist = d; best = p; *outPos = ePos; }
    }
    return best;
}

// ============ ХУК 1: SetGunTargetPoint ============
static void (*orig_SetGunTargetPoint)(void* self, struct Vector3 v) = NULL;

static void hook_SetGunTargetPoint(void* self, struct Vector3 v) {
    if (!silentAimEnabled || !get_LocalPlayer) {
        orig_SetGunTargetPoint(self, v); return;
    }
    void* lp = get_LocalPlayer();
    if (!lp || self != lp) { orig_SetGunTargetPoint(self, v); return; }

    struct Vector3 ePos;
    if (find_closest_enemy(lp, &ePos)) {
        orig_SetGunTargetPoint(self, ePos);
    } else {
        orig_SetGunTargetPoint(self, v);
    }
}

// ============ ХУК 2: SetTargetAndLookPoint ============
static void (*orig_SetTargetAndLookPoint)(void* self, struct Vector3 point, bool sniper, bool force) = NULL;

static void hook_SetTargetAndLookPoint(void* self, struct Vector3 point, bool sniper, bool force) {
    if (!silentAimEnabled || !get_LocalPlayer || !useLookPointHook) {
        orig_SetTargetAndLookPoint(self, point, sniper, force); return;
    }
    void* lp = get_LocalPlayer();
    if (!lp || self != lp) { orig_SetTargetAndLookPoint(self, point, sniper, force); return; }

    struct Vector3 ePos;
    if (find_closest_enemy(lp, &ePos)) {
        orig_SetTargetAndLookPoint(self, ePos, sniper, true);
    } else {
        orig_SetTargetAndLookPoint(self, point, sniper, force);
    }
}

// ============ ИНИЦИАЛИЗАЦИЯ ============
%ctor {
    unityBase = get_unity_base();
    if (!unityBase) { NSLog(@"[Tweak] UnityFramework not found"); return; }

    NSLog(@"[Tweak] UnityBase: 0x%lx", (unsigned long)unityBase);

    get_LocalPlayer = (void*(*)())(unityBase + GET_LOCAL_PLAYER_RVA);
    get_PlayerListOthers = (void*(*)())(unityBase + GET_PLAYER_LIST_OTHERS_RVA);

    MSHookFunction((void*)(unityBase + SET_GUN_TARGET_POINT_RVA),
                   (void*)hook_SetGunTargetPoint,
                   (void**)&orig_SetGunTargetPoint);

    MSHookFunction((void*)(unityBase + SET_TARGET_LOOK_POINT_RVA),
                   (void*)hook_SetTargetAndLookPoint,
                   (void**)&orig_SetTargetAndLookPoint);

    NSLog(@"[Tweak] Hooks installed");
}
