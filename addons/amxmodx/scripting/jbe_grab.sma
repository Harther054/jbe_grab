#include <amxmodx>
#include <fakemeta>
#include <reapi>
#include <xs>

//Закомментируйте, если не хотите чтобы конфиг кваров создавался автоматически.
#define CONFIG_CVAR

#define AUTHOR          "by fgd"
#define VERSION         "1.0.0b"
#define PLUGIN_NAME     "jbe_grab"

#define GetLang(%0)     (fmt("%L", LANG_SERVER, %0)) 
#define IsAccess(%0,%1)        (get_user_flags(%0) & %1)

#define LS  LANG_SERVER    

//Для удобного чтения координат.
enum _:XYZ {Float: X, Float: Y, Float: Z};

enum _: eDataPlayers {GRABBER, GRABBED, GRAB_LEN};

enum _: eCvars     
{
    CVAR_GRAB_ACCESS[6],                 //флаг доступа к грабу
    CVAR_GRAB_MENU_ACCESS[6],            //флаг доступа к меню граба
    CVAR_GRAB_IMMUNITY_ACCESS[6],        //флаг доступа к иммунитету
    CVAR_GRAB_EDIT_MENU_ACCESS[6],       //флаг доступа к меню редактирование граба
    CVAR_GRAB_MAIN_ADMIN[6],             //флаг доступа Гл.Админа(Перехват + Игнор иммунитета)
}

enum _: eDataGrab
{
    bool: GRAB_IMMUNITY                  //переключатель иммунитета(вкл/выкл)
}

new g_Cvars[eCvars];
new g_DataPlayers[MAX_PLAYERS + 1][eDataPlayers];
new g_DataGrab[MAX_PLAYERS + 1][eDataGrab];

new g_iBitFlagAccess, g_iBitFlagGrabMenu, g_iBitFlagImmunity, g_iBitFlagEditMenu, g_iBitFlagMainAdmin;

public plugin_init()
{
    register_plugin(PLUGIN_NAME, VERSION, AUTHOR);

    CreateLang();
    register_dictionary(fmt("%s.txt", PLUGIN_NAME));

    CreateCvars();

    register_clcmd("+grab", "OnGrab");
    register_clcmd("-grab", "OffGrab");
    register_clcmd("drop", "GrabThrow");

    register_clcmd("grab_immunity", "Clcmd_MenuImmunity");

    RegisterHookChain(RG_CBasePlayer_PreThink, "Hook_PreThink", false);

    g_iBitFlagAccess = read_flags(g_Cvars[CVAR_GRAB_ACCESS]);
    g_iBitFlagGrabMenu = read_flags(g_Cvars[CVAR_GRAB_MENU_ACCESS]);
    g_iBitFlagImmunity = read_flags(g_Cvars[CVAR_GRAB_IMMUNITY_ACCESS]);
    g_iBitFlagEditMenu = read_flags(g_Cvars[CVAR_GRAB_EDIT_MENU_ACCESS]);
    g_iBitFlagMainAdmin = read_flags(g_Cvars[CVAR_GRAB_MAIN_ADMIN]);
}

public OnGrab(id)
{
    if(IsAccess(id, g_iBitFlagAccess))
        g_DataPlayers[id][GRABBED] = -1;
    else 
        client_print_color(id, print_team_red, "%s %s", GetLang("GRAB_CHAT_PREFIX"), GetLang("GRAB_CHAT_NO_ACCESS"));
    return PLUGIN_HANDLED;
}

public OffGrab(id)
{
    unset_grabbed(id);
    return PLUGIN_HANDLED;
}

public Hook_PreThink(id)
{
    static iTarget;

    if(g_DataPlayers[id][GRABBED] == -1)
    {
        static Float:fStartPos[XYZ], Float: fEndPos[XYZ];

        //получаем коодинаты вгляда игрока.
        get_viewofs_pos(id, fStartPos);
        
        //Определения координат точки, на которую направлен взгляд игрока.
        fEndPos = get_my_aim(id, 9999);

        //получаем точку пересечения.
        xs_vec_add(fStartPos, fEndPos, fEndPos);

        iTarget = get_traceline(fStartPos, fEndPos, id, fEndPos)

        if(0 < iTarget <= MaxClients)
        {
            //проверка схвачен игрок или нет.
            if(is_grabbed(id, iTarget))
            {
                client_print_color(id, print_team_red, "%L %L", LS, "GRAB_CHAT_PREFIX", LS, "GRAB_CHAT_IS_GRABBED", iTarget, g_DataPlayers[iTarget][GRABBER]);
                unset_grabbed(id);
                return HC_SUPERCEDE;
            }
            if(g_DataGrab[iTarget][GRAB_IMMUNITY] && !IsAccess(id, g_iBitFlagMainAdmin))
            {
                client_print_color(id, print_team_red, "%L %L", LS, "GRAB_CHAT_PREFIX", LS, "GRAB_CHAT_ID_IMMUNITY", iTarget);
                client_print_color(iTarget, print_team_red, "%L %L", LS, "GRAB_CHAT_PREFIX", LS, "GRAB_CHAT_TARGET_IMMUNITY", id);
                unset_grabbed(id);
                return HC_SUPERCEDE;
            }
            set_grabber(id, iTarget);
        }
        else 
        {
            new movetype;
            if(!is_nullent(iTarget))
            {
                movetype = get_entvar(iTarget, var_movetype);
                if(!(movetype == MOVETYPE_STEP || movetype == MOVETYPE_TOSS || movetype == MOVETYPE_WALK))
                    return HC_SUPERCEDE;
            }
            else 
            {
                iTarget = 0;
                new iEnt = MAX_PLAYERS + 1; //пропускаем игроков.
                engfunc(EngFunc_FindEntityInSphere, iEnt, fEndPos, 12.0);
                while(!iTarget && iEnt > 0)
                {
                    movetype = get_entvar(iEnt, var_movetype);
                    if((movetype == MOVETYPE_STEP || movetype == MOVETYPE_TOSS || movetype == MOVETYPE_WALK) && iEnt != id)
                        iTarget = iEnt;
                    iEnt = engfunc(EngFunc_FindEntityInSphere, iEnt, fEndPos, 12.0);
                }
            }
            if(iTarget)
            {
                if(is_grabbed(id, iTarget))
                    return HC_SUPERCEDE;
                set_grabber(id, iTarget);
            }
        }
    }

    iTarget = g_DataPlayers[id][GRABBED];
    if(iTarget > 0)
    {
        if(is_nullent(iTarget) || (get_entvar(iTarget, var_health) < 1) && (get_entvar(iTarget, var_max_health)) || !is_user_alive(id))
        {
            unset_grabbed(id);
            return HC_SUPERCEDE;
        }

        if(iTarget > MaxClients)
            GrabThink(id);
    
        set_button_push_pull(id, iTarget);
    }

    iTarget = g_DataPlayers[id][GRABBER];

    if(iTarget > 0)
        GrabThink(iTarget);

    return HC_CONTINUE;
}

public GrabThink(const id)
{
    new iTarget = g_DataPlayers[id][GRABBED];
    if(get_entvar(iTarget, var_movetype) == MOVETYPE_FLY && !(get_entvar(iTarget, var_button) & IN_JUMP)) client_cmd(iTarget, "+jump;wait;-jump");

    new Float:f_pVOrigin[XYZ];
    get_viewofs_pos(id, f_pVOrigin);
    
    new Float: f_pEndPos[XYZ];
    f_pEndPos = get_my_aim(id, g_DataPlayers[id][GRAB_LEN]);

    new Float: f_tOrigin[XYZ];
    f_tOrigin = get_target_origin_f(iTarget);

    new fVelocity[XYZ];
    fVelocity[X] = ((f_pVOrigin[X] + f_pEndPos[X]) - f_tOrigin[X]) * 8;
    fVelocity[Y] = ((f_pVOrigin[Y] + f_pEndPos[Y]) - f_tOrigin[Y]) * 8;
    fVelocity[Z] = ((f_pVOrigin[Z] + f_pEndPos[Z]) - f_tOrigin[Z]) * 8;

    if(is_user_connected(id))
        set_member(id, m_flNextAttack, 1.0);

    set_entvar(iTarget, var_velocity, fVelocity);
}

// Отслеживаем кнопки правую и левую кнопку мыши.
public set_button_push_pull(const id, const iTarget)
{
    new iButton = get_entvar(id, var_button);

    if(iButton & IN_ATTACK)
        if(g_DataPlayers[id][GRAB_LEN] < 9999)
            g_DataPlayers[id][GRAB_LEN] += 15;

    if(iButton & IN_ATTACK2)
        if(g_DataPlayers[id][GRAB_LEN] > 90)
            g_DataPlayers[id][GRAB_LEN] -= 10;
}

// Вычисляем координаты взгляда игрока.
public get_viewofs_pos(const id, Float:f_pVOrigin[XYZ])
{
    new Float:f_pOrigin[XYZ];
    get_entvar(id, var_origin, f_pOrigin);
    get_entvar(id, var_view_ofs, f_pVOrigin);

    xs_vec_add(f_pOrigin, f_pVOrigin, f_pVOrigin); 
}
// Выполняет функцию броска игрока.
public GrabThrow(id)
{
    new iTarget = g_DataPlayers[id][GRABBED];

    if(iTarget > 0)
    {
        set_entvar(iTarget, var_velocity, get_my_aim(id, 1500));
        unset_grabbed(id);
        return PLUGIN_HANDLED;
    }
    return PLUGIN_CONTINUE;
}

// Меню иммунитета 
public Clcmd_MenuImmunity(id)
{
    if(!IsAccess(id, g_iBitFlagImmunity))
    {
        client_print_color(id, print_team_red, "%L %L", LS, "GRAB_CHAT_PREFIX", LS, "GRAB_CHAT_NO_FLAG_IMMUNITY")
        return PLUGIN_HANDLED;
    }

    new iImmunityMenu = menu_create(GetLang("GRAB_MENU_IMMUNITY"), "Handler_MenuImmunity");

    menu_setprop(iImmunityMenu, MPROP_EXITNAME, GetLang("GRAB_MENU_ITEM_EXIT"));

    menu_additem(iImmunityMenu, fmt("%L %L", LS, "GRAB_MENU_ITEM_IMMUNITY",  LS, !g_DataGrab[id][GRAB_IMMUNITY] ? "GRAB_MENU_TOGGLE_OFF" : "GRAB_MENU_TOGGLE_ON"));

    menu_display(id, iImmunityMenu);
    return PLUGIN_HANDLED;
}

public Handler_MenuImmunity(const id, const iImmunityMenu, const iImmunityItemMenu)
{
    if(iImmunityItemMenu == MENU_EXIT)
    {
        menu_destroy(iImmunityMenu);
        return PLUGIN_HANDLED;
    }

    menu_destroy(iImmunityMenu);

    switch(iImmunityItemMenu)
    {
        case 0: g_DataGrab[id][GRAB_IMMUNITY] ^= true;    
    }

    Clcmd_MenuImmunity(id);
    return PLUGIN_HANDLED;
}

// Автоматически создаёт cfg файл.
CreateCvars()
{
    bind_pcvar_string(
        create_cvar(
            .name = "jbe_grab_access",
            .string = "r",
            .description = GetLang("GRAB_CVAR_ACCESS")
        ), g_Cvars[CVAR_GRAB_ACCESS], charsmax(g_Cvars[CVAR_GRAB_ACCESS])
    );

    bind_pcvar_string(
        create_cvar(
            .name = "jbe_grab_menu_access",
            .string = "u",
            .description = GetLang("GRAB_CVAR_MENU_ACCESS")
        ), g_Cvars[CVAR_GRAB_MENU_ACCESS], charsmax(g_Cvars[CVAR_GRAB_MENU_ACCESS])
    );

    bind_pcvar_string(
        create_cvar(
            .name = "jbe_grab_immunity_access",
            .string = "a",
            .description = GetLang("GRAB_CVAR_IMMUNITY_ACCESS")
        ), g_Cvars[CVAR_GRAB_IMMUNITY_ACCESS], charsmax(g_Cvars[CVAR_GRAB_IMMUNITY_ACCESS])
    );

    bind_pcvar_string(
        create_cvar(
            .name = "jbe_grab_edit_menu_access",
            .string = "d",
            .description = GetLang("GRAB_CVAR_EDIT_MENU_ACCESS")
        ), g_Cvars[CVAR_GRAB_EDIT_MENU_ACCESS], charsmax(g_Cvars[CVAR_GRAB_EDIT_MENU_ACCESS])
    );

    bind_pcvar_string(
        create_cvar(
            .name = "jbe_grab_edit_main_admin",
            .string = "l",
            .description = GetLang("GRAB_CVAR_MAIN_ADMIN_ACCESS")
        ), g_Cvars[CVAR_GRAB_MAIN_ADMIN], charsmax(g_Cvars[CVAR_GRAB_MAIN_ADMIN])
    );


    #if defined CONFIG_CVAR
        AutoExecConfig(true, "jbe_grab", "jbe_grab");
    #endif
}

// Автоматически создаёт Lang файл.
CreateLang()
{
    new szData[256];
    formatex(szData, charsmax(szData), "addons/amxmodx/data/lang/%s.txt", PLUGIN_NAME);

    if(!file_exists(szData))
        write_file(szData,
        "[ru]^n\
        GRAB_CHAT_PREFIX = ^^3[^^4JBE GRAB^^3]^n\
        GRAB_CHAT_IS_GRABBED = ^^1Игрок ^^4%n ^^1уже в руках ^^3%n^n\
        GRAB_CHAT_NO_ACCESS = ^^1У вас нет ^^3доступа ^^1для использования ^^4граба^n\
        GRAB_CHAT_NO_FLAG_IMMUNITY = ^^1У вас нет ^^3доступа ^^1 к меню ^4иммунитета^n\
        GRAB_CHAT_TARGET_IMMUNITY = ^^1Администратор ^^4%n ^1пытается взять вас ^3грабом^n\
        GRAB_CHAT_ID_IMMUNITY = ^^1У игрока ^4%n ^1включён ^3иммунитет^n\
        GRAB_MENU_IMMUNITY = \wГраб меню \d| \yИммунитет меню^n\
        GRAB_MENU_ITEM_IMMUNITY = Иммунитет:^n\
        GRAB_MENU_TOGGLE_ON = \yВкл^n\
        GRAB_MENU_TOGGLE_OFF = \rВыкл^n\
        GRAB_MENU_ITEM_EXIT = Выход^n\
        GRAB_CVAR_ACCESS = Флаг доступа к грабу^n\
        GRAB_CVAR_MENU_ACCESS = Флаг доступа к меню граба^n\
        GRAB_CVAR_IMMUNITY_ACCESS = Флаг доступа к иммунитету от граба^n\
        GRAB_CVAR_EDIT_MENU_ACCESS = Флаг доступа к меню редактирования граба^n\
        GRAB_CVAR_MAIN_ADMIN_ACCESS = Флаг доступа главного админа(перехват + игнор иммунитета)^n\
        [en]^n\
        GRAB_CHAT_PREFIX = ^^3[^^4JBE GRAB^^3]^n\
        GRAB_CHAT_IS_GRABBED = ^^1 Player ^^4%n ^^1is already in the hands of ^^3%n^n\
        GRAB_NO_ACCESS = ^^1 You do ^^3not have access ^^1to use ^^4grab^n\
        GRAB_CHAT_NO_FLAG_IMMUNITY = ^^1You do not have ^^3access ^^1to the ^4immunity menu^n\
        GRAB_CHAT_TARGET_IMMUNITY = ^^1Admin ^^4%n ^1is trying to grab you ^3by force^n\
        GRAB_CHAT_ID_IMMUNITY = ^^Player ^4%n has ^3immunity ^1enabled^n\
        GRAB_MENU_IMMUNITY = \wGrab menu \d| \yImmunity menu^n\
        GRAB_MENU_ITEM_IMMUNITY = Immunity:^n\
        GRAB_MENU_TOGGLE_ON = \yOn^n\
        GRAB_MENU_TOGGLE_OFF = \rOff^n\
        GRAB_MENU_ITEM_EXIT = Exit^n\
        GRAB_CVAR_ACCESS = Access flag for grab^n\
        GRAB_CVAR_MENU_ACCESS = Access flag for the grab menu^n\
        GRAB_CVAR_IMMUNITY_ACCESS = Access flag for immunity from grab^n\
        GRAB_CVAR_EDIT_MENU_ACCESS = Access flag for the grab edit menu^n\
        GRAB_CVAR_MAIN_ADMIN_ACCESS = Access flag for the head admin (interception + ignore immunity)");
}

// Определяет координаты, куда смотрит игрок.
// Возвращает вектор с координатами направления взгляда игрока умноженными на заданную длину len.
stock Float: get_my_aim(const id, len = 1)
{
    // Получаем углы обзора игрока.
    new Float: f_pVAngels[XYZ];
    get_entvar(id, var_v_angle, f_pVAngels);

    // Преобразуем углы в вектор направления взгляда.
    engfunc(EngFunc_MakeVectors, f_pVAngels);
    global_get(glb_v_forward, f_pVAngels);

    // Умножаем вектор направления на заданную длину len.
    xs_vec_mul_scalar(f_pVAngels, float(len), f_pVAngels)
    return f_pVAngels
}

// Выполняет трассировку линии от точки fStartPos до fEndPos и определяет, куда линия попадает.
// Возвращает идентификатор сущности, в которую попала линия.
stock get_traceline(const Float:fStartPos[XYZ], const Float:fEndPos[3], IGNOREED, Float:vHitPos[XYZ])
{   
    engfunc(EngFunc_TraceLine, fStartPos, fEndPos, DONT_IGNORE_MONSTERS, IGNOREED, 0);
    get_tr2(0, TR_vecEndPos, vHitPos);
    return get_tr2(0, TR_pHit);
}

// Проверяет, схвачен ли игрок или объект другим игроком.
// Возвращает true, если цель схвачена другим игроком, и false в противном случае.
stock is_grabbed(const id, const Target)
{
    for(new iPlayer = 1; iPlayer <= MaxClients; iPlayer++)
    {
        if(g_DataPlayers[iPlayer][GRABBED] == Target)
        {
            unset_grabbed(id);
            return true;
        }
    }
    
    return false;
}

// Отменяет захват цели игроком и сбрасывает состояние захвата.
stock unset_grabbed(const id)
{
    new iTarget = g_DataPlayers[id][GRABBED];
    if(!is_nullent(iTarget))
    {
        rg_set_rendering(iTarget, kRenderFxNone, 0, 0, 0, kRenderNormal, 255);

        if(0 < iTarget <= MaxClients)
            g_DataPlayers[iTarget][GRABBER] = 0;

        show_menu(id, 0, "^n");

        if(is_user_connected(id))
            set_member(id, m_flNextAttack, 0.0);
    }
    g_DataPlayers[id][GRABBED] = 0;
}

// Устанавливает игрока id в качестве захватчика для цели iTarget.
stock set_grabber(const id, const iTarget)
{
    rg_set_rendering(iTarget, kRenderFxGlowShell, 255, 255, 255, _, 50);

    if(0 < iTarget <= MaxClients)
    {
        g_DataPlayers[iTarget][GRABBER] = id;
    }
    g_DataPlayers[id][GRABBED] = iTarget;

    // Получаем текущие координаты игрока id и цели iTarget.
    new Float: f_pOrigin[XYZ], Float: f_tOrigin[XYZ];

    get_entvar(id, var_origin, f_pOrigin);
    get_entvar(iTarget, var_origin, f_tOrigin);

    // Вычисляем расстояние между игроком и целью и округляем до ближайшего целого числа.
    g_DataPlayers[id][GRAB_LEN] = floatround(get_distance_f(f_pOrigin, f_tOrigin));

    // Проверяем и устанавливаем минимальную дистанцию между игроками.
    if(g_DataPlayers[id][GRAB_LEN] < 90)
        g_DataPlayers[id][GRAB_LEN] = 90;
}

//отвечает за свечения игрока.
stock rg_set_rendering(const id, const iRenderFx = kRenderFxNone, const R = 0, const G = 0, const B = 0, const iRenderMode = kRenderNormal, const iRenderAmount = 0)
{
    new Float:flRenderColor[3];

    flRenderColor[0] = float(R);
    flRenderColor[1] = float(G);
    flRenderColor[2] = float(B);

    set_entvar(id, var_renderfx, iRenderFx);
    set_entvar(id, var_rendercolor, flRenderColor);
    set_entvar(id, var_rendermode, iRenderMode);
    set_entvar(id, var_renderamt, float(iRenderAmount));
}

// Получает координаты центра цели с учётом её размеров, если это не игрок.
stock Float:get_target_origin_f(id) {
	new Float:orig[XYZ];
	get_entvar(id, var_origin, orig);
	
	if(id > MaxClients)
	{
         // Получаем минимальные и максимальные координаты размеров цели
		new Float:mins[XYZ], Float:maxs[XYZ];
		get_entvar(id, var_mins, mins);
		get_entvar(id, var_maxs, maxs);
		
        // Если минимальная координата по Z равна нулю, корректируем Z координату центра цели.
		if(!mins[Z]) orig[Z] += maxs[Z] / 2;
	}
	
	return orig;
}

