#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <cstrike>
#include <sdktools>
#include <sdkhooks>
#include <clientmod>
#include <clientmod\tracerayfilter>

ConVar g_hPickup = null;
ConVar sv_turbophysics = null;
bool bTurboPhysicsEnabled = false;
float fLastWeaponDrop[MAXPLAYERS][4096];
Handle hBumpWeapon = INVALID_HANDLE;

public Plugin myinfo = 
{
	name = "Pickup Weapon [Using Use Key]",
	author = CM_AUTHOR,
	description = "Allows players to pickup weapon using [USE] key. Press E.",
	version = "1.0",
	url = CM_URL
};

public void OnPluginStart()
{
	g_hPickup = CreateConVar("se_use_weapon_pickup", /*не трогать*/"0"/*do not touch*/, "", FCVAR_REPLICATED, true, 0.0, true, 1.0);
	sv_turbophysics = FindConVar("sv_turbophysics");
	
	Handle hConfig = LoadGameConfigFile("clientmod_pickup");
	if(hConfig == INVALID_HANDLE)
	{
		SetFailState("Load clientmod_pickup gamedata Config Fail");
	}
	
	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(hConfig, SDKConf_Signature, "BumpWeapon");
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	hBumpWeapon = EndPrepSDKCall();
	
	CloseHandle(hConfig);
	
	if (hBumpWeapon == INVALID_HANDLE)
	{
		SetFailState("Failed EndPrepSDKCall for BumpWeapon");
	}
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientConnected(i) && !IsFakeClient(i))
		{
			if (IsClientInGame(i))
			{
				OnClientPutInServer(i);
			}
		}
	}
}

public void OnClientPutInServer(int client)
{
	if (!IsFakeClient(client))
	{
		SDKHook(client, SDKHook_PreThink, OnClientPreThink);
		SDKHook(client, SDKHook_Think, OnClientThink);
	}
}

public bool Filter_LocalPlayer(int entity, int mask, any target)
{
	if (!CM_DefaultFilter(entity, target, mask))
		return false;
		
	if (entity == target || entity < 1)
		return false;
		
	return true;
}

int GetWeaponEntity(int entity)
{
	if (entity < 1)
		return 0;
	
	if (GetEntityMoveType(entity) != MOVETYPE_VPHYSICS)
		return 0;
		
	CM_Collision_Group_t collisionGroup = view_as<CM_Collision_Group_t>(GetEntProp(entity, Prop_Send, "m_CollisionGroup", 1));
	if (collisionGroup != CM_COLLISION_GROUP_WEAPON)
		return 0;
		
		
	return entity;
}

public void OnClientPreThink(int client)
{
	if (!g_hPickup.BoolValue || !IsPlayerAlive(client))
	{
		return;
	}
	
	if (GetClientButtons(client) & IN_USE)
	{
		float eye_pos[3]; GetClientEyePosition(client, eye_pos);
		float eye_angle[3]; GetClientEyeAngles(client, eye_angle);
		float fwd[3], right[3], up[3]; GetAngleVectors(eye_angle, fwd, right, up);
		float end_pos[3]; 
		
		if (sv_turbophysics.BoolValue)
		{
			end_pos[0] = fwd[0]; end_pos[1] = fwd[1]; end_pos[2] = fwd[2];
			ScaleVector(end_pos, 96.0); AddVectors(eye_pos, end_pos, end_pos);
			
			TR_TraceRayFilter(eye_pos, end_pos, MASK_SOLID, RayType_EndPoint, Filter_LocalPlayer, client);
			if (GetWeaponEntity(TR_GetEntityIndex()) > 0)
			{
				CSWeaponID weapon_id = GetWeaponID(GetWeaponEntity(TR_GetEntityIndex()));
				if (IsPrimaryWeapon(weapon_id) || IsSecondaryWeapon(weapon_id))
				{
					sv_turbophysics.SetBool(false);
					bTurboPhysicsEnabled = true;
				}
			}
		}
		
		if (GetEntProp(client, Prop_Data, "m_afButtonPressed") & IN_USE)
		{
			ScaleVector(fwd, 128.0);
			AddVectors(eye_pos, fwd, end_pos);
			
			TR_TraceRayFilter(eye_pos, end_pos, MASK_ALL, RayType_EndPoint, Filter_LocalPlayer, client);
			int weapon = GetWeaponEntity(TR_GetEntityIndex());
			if (weapon > 0 && GetGameTime() - fLastWeaponDrop[client][weapon] > 1.0)
			{
				CSWeaponID weapon_id = GetWeaponID(weapon);
				if (!IsPrimaryWeapon(weapon_id) && !IsSecondaryWeapon(weapon_id))
				{
					return;
				}
				if (IsPrimaryWeapon(weapon_id) && GetPlayerWeaponSlot(client, CS_SLOT_PRIMARY) > -1)
				{
					CS_DropWeapon(client, GetPlayerWeaponSlot(client, CS_SLOT_PRIMARY), false, false);
				}
				else if (IsSecondaryWeapon(weapon_id) && GetPlayerWeaponSlot(client, CS_SLOT_SECONDARY) > -1)
				{
					CS_DropWeapon(client, GetPlayerWeaponSlot(client, CS_SLOT_SECONDARY), false, false);
				}
				
				SDKCall(hBumpWeapon, client, weapon);
			}
		}
	}
}

public void OnClientThink(int client)
{
	if (bTurboPhysicsEnabled)
	{
		bTurboPhysicsEnabled = false;
		sv_turbophysics.SetBool(true);
	}
}

public Action CS_OnCSWeaponDrop(int client, int weaponIndex)
{
	fLastWeaponDrop[client][weaponIndex] = GetGameTime();
}

CSWeaponID GetWeaponID(int entity)
{
	char weapon_name[64];
	if (GetEntityClassname(entity, weapon_name, sizeof(weapon_name)) && strlen(weapon_name) > 7)
	{
		return CS_AliasToWeaponID(weapon_name[7]);
	}
	return CSWeapon_NONE;
}

bool IsPrimaryWeapon(CSWeaponID id)
{
	switch (id)
	{
		case CSWeapon_SCOUT,
		CSWeapon_XM1014,
		CSWeapon_MAC10,
		CSWeapon_AUG,
		CSWeapon_UMP45,
		CSWeapon_SG550,
		CSWeapon_GALIL,
		CSWeapon_FAMAS,
		CSWeapon_AWP,
		CSWeapon_MP5NAVY,
		CSWeapon_M249,
		CSWeapon_M3,
		CSWeapon_M4A1,
		CSWeapon_TMP,
		CSWeapon_G3SG1,
		CSWeapon_SG552,
		CSWeapon_AK47,
		CSWeapon_P90:
			return true;
	}
	return false;
}

bool IsSecondaryWeapon(CSWeaponID id)
{
	switch( id )
	{
		case CSWeapon_USP,
		CSWeapon_GLOCK,
		CSWeapon_DEAGLE,
		CSWeapon_ELITE,
		CSWeapon_P228,
		CSWeapon_FIVESEVEN:
			return true;
	}

	return false;
}