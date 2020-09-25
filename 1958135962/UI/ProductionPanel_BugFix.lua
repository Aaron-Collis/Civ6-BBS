-- Copyright 2018-2019, Firaxis Games.

include("ProductionPanel");

print("ProductionPanel Bugfix for PBC")

-- ===========================================================================
--	MEMBERS
-- ===========================================================================
-- Mirrored in CityPanel
local LISTMODE:table = {PRODUCTION = 1, PURCHASE_GOLD = 2, PURCHASE_FAITH = 3, PROD_QUEUE = 4};

-- ===========================================================================
--	OVERRIDES
-- ===========================================================================

-- ===========================================================================
function GetData()
	print("GetData() ProductionPanel")
	local playerID	:number = Game.GetLocalPlayer();
	local pPlayer	:table = Players[playerID];
	if (pPlayer == nil) then
		Close();
		return nil;
	end

	local pSelectedCity:table = UI.GetHeadSelectedCity();
	if pSelectedCity == nil then
		Close();
		return nil;
	end

	local cityGrowth	= pSelectedCity:GetGrowth();
	local cityCulture	= pSelectedCity:GetCulture();
	local buildQueue	= pSelectedCity:GetBuildQueue();
	local playerTreasury= pPlayer:GetTreasury();
	local playerReligion= pPlayer:GetReligion();
	local cityGold		= pSelectedCity:GetGold();
	local cityBuildings = pSelectedCity:GetBuildings();
	local cityDistricts = pSelectedCity:GetDistricts();
	local cityID		= pSelectedCity:GetID();
		
	local new_data = {
		City				= pSelectedCity,
		Population			= pSelectedCity:GetPopulation(),
		Owner				= pSelectedCity:GetOwner(),
		Damage				= pPlayer:GetDistricts():FindID( pSelectedCity:GetDistrictID() ):GetDamage(),
		TurnsUntilGrowth	= cityGrowth:GetTurnsUntilGrowth(),
		CurrentTurnsLeft	= buildQueue:GetTurnsLeft(),
		FoodSurplus			= cityGrowth:GetFoodSurplus(),
		CulturePerTurn		= cityCulture:GetCultureYield(),
		TurnsUntilExpansion = cityCulture:GetTurnsUntilExpansion(),
		DistrictItems		= {},
		BuildingItems		= {},
		UnitItems			= {},
		ProjectItems		= {},
		BuildingPurchases	= {},
		UnitPurchases		= {},
		DistrictPurchases	= {},
	};
		
	m_CurrentProductionHash = buildQueue:GetCurrentProductionTypeHash();
	m_PreviousProductionHash = buildQueue:GetPreviousProductionTypeHash();

	--Must do districts before buildings
	for row in GameInfo.Districts() do
		if row.Hash == m_CurrentProductionHash then
			new_data.CurrentProduction = row.Name;
				
			if(GameInfo.DistrictReplaces[row.DistrictType] ~= nil) then
				new_data.CurrentProductionType = GameInfo.DistrictReplaces[row.DistrictType].ReplacesDistrictType;
			else
				new_data.CurrentProductionType = row.DistrictType;
			end
		end
			
		local isInPanelList 		:boolean = (row.Hash ~= m_CurrentProductionHash or not row.OnePerCity) and not row.InternalOnly;
		local bHasProducedDistrict	:boolean = cityDistricts:HasDistrict( row.Index );
		if isInPanelList and ( buildQueue:CanProduce( row.Hash, true ) or bHasProducedDistrict ) then
			local isCanProduceExclusion, results = buildQueue:CanProduce( row.Hash, false, true );
			local isDisabled			:boolean = not isCanProduceExclusion;
				
			-- If at least one valid plot is found where the district can be built, consider it buildable.
			local plots :table = GetCityRelatedPlotIndexesDistrictsAlternative( pSelectedCity, row.Hash );
			if plots == nil or table.count(plots) == 0 then
				-- No plots available for district. Has player had already started building it?
				local isPlotAllocated :boolean = false;
				local pDistricts 		:table = pSelectedCity:GetDistricts();
				for _, pCityDistrict in pDistricts:Members() do
					if row.Index == pCityDistrict:GetType() then
						isPlotAllocated = true;
						break;
					end
				end
				-- If not, this district can't be built. Guarantee that isDisabled is set.
				if not isPlotAllocated then
					isDisabled = true;
				elseif results ~= nil then
					local pFailureReasons : table = results[CityCommandResults.FAILURE_REASONS];
					if pFailureReasons ~= nil and table.count( pFailureReasons ) > 0 then
						for i,v in ipairs(pFailureReasons) do
							if v == TXT_DISTRICT_REPAIR_LOCATION_FLOODED then
								isDisabled = true;
								break;
							end
						end
					end
				end
			elseif isDisabled and results ~= nil then
				-- TODO this should probably be handled in the exposure, for example:
				-- BuildQueue::CanProduce(nDistrictHash, bExclusionTest, bReturnResults, bAllowPurchasingPlots)
				local pFailureReasons : table = results[CityCommandResults.FAILURE_REASONS];
				if pFailureReasons ~= nil and table.count( pFailureReasons ) > 0 then
					-- There are available plots to purchase, it could still be available
					isDisabled = false;
					for i,v in ipairs(pFailureReasons) do
						-- If its disabled for another reason, keep it disabled
						if v ~= "LOC_DISTRICT_ZONE_NO_SUITABLE_LOCATION" then
							isDisabled = true;
							break;
						end
					end
				end
			end
				
			local allReasons			:string = ComposeFailureReasonStrings( isDisabled, results );
			local sToolTip				:string = ToolTipHelper.GetToolTip(row.DistrictType, Game.GetLocalPlayer()) .. allReasons;
				
			local iProductionCost		:number = buildQueue:GetDistrictCost( row.Index );
			local iProductionProgress	:number = buildQueue:GetDistrictProgress( row.Index );

			sToolTip = sToolTip .. "[NEWLINE][NEWLINE]";
			sToolTip = sToolTip .. ComposeProductionCostString( iProductionProgress, iProductionCost);

			local iMaintenanceCost		:number = row.Maintenance or 0;
			if (iMaintenanceCost ~= nil and iMaintenanceCost > 0) then
				local yield = GameInfo.Yields["YIELD_GOLD"];
				if(yield) then
					sToolTip = sToolTip .. "[NEWLINE]" .. Locale.Lookup("LOC_TOOLTIP_MAINTENANCE", iMaintenanceCost, yield.IconString, yield.Name);
				end
			end

			local bIsContaminated:boolean = cityDistricts:IsContaminated( row.Index );
			local iContaminatedTurns:number = 0;
			if bIsContaminated then
				for _, pDistrict in cityDistricts:Members() do
					local kDistrictDef:table = GameInfo.Districts[pDistrict:GetType()];
					if kDistrictDef.PrimaryKey == row.DistrictType then
						local kFalloutManager = Game.GetFalloutManager();
						local pDistrictPlot:table = Map.GetPlot(pDistrict:GetX(), pDistrict:GetY());
						iContaminatedTurns = kFalloutManager:GetFalloutTurnsRemaining(pDistrictPlot:GetIndex());
					end
				end
			end

			table.insert( new_data.DistrictItems, {
				Type				= row.DistrictType, 
				Name				= row.Name, 
				ToolTip				= sToolTip, 
				Hash				= row.Hash, 
				Kind				= row.Kind, 
				TurnsLeft			= buildQueue:GetTurnsLeft( row.DistrictType ), 
				Disabled			= isDisabled, 
				Repair				= cityDistricts:IsPillaged( row.Index ),
				Contaminated		= bIsContaminated,
				ContaminatedTurns	= iContaminatedTurns,
				Cost				= iProductionCost, 
				Progress			= iProductionProgress,
				HasBeenBuilt		= bHasProducedDistrict,
				IsComplete			= cityDistricts:IsComplete( row.Index )
			});
		end

		-- Can it be purchased with gold?
		local isAllowed, kDistrict = ComposeDistrictForPurchase( row, pSelectedCity, "YIELD_GOLD", playerTreasury, "LOC_BUILDING_INSUFFICIENT_FUNDS" );
		if isAllowed then
			table.insert( new_data.DistrictPurchases, kDistrict );
		end

		-- Can it be purchased with faith?
		local isAllowed, kDistrict = ComposeDistrictForPurchase( row, pSelectedCity, "YIELD_FAITH", playerReligion, "LOC_BUILDING_INSUFFICIENT_FAITH" );
		if isAllowed then
			table.insert( new_data.DistrictPurchases, kDistrict );
		end
	end

	local unitData;
	unitData = new_data.UnitPurchases;
	for i, item in ipairs(unitData) do
		print("STEP1","item.Yield",item.Yield,"item.Type",item.Type,"item.Name",item.Name)	
	end

	--Must do buildings after districts
	for row in GameInfo.Buildings() do
		if row.Hash == m_CurrentProductionHash then
			new_data.CurrentProduction = row.Name;
			new_data.CurrentProductionType= row.BuildingType;
		end

		local bCanProduce = buildQueue:CanProduce( row.Hash, true );
		local iPrereqDistrict = "";
		if row.PrereqDistrict ~= nil then
			iPrereqDistrict = row.PrereqDistrict;
				
			--Only add buildings if the prereq district is not the current production (this can happen when repairing)
			if new_data.CurrentProductionType == row.PrereqDistrict then
				bCanProduce = false;
			end
		end

		if row.Hash ~= m_CurrentProductionHash and (not row.MustPurchase or cityBuildings:IsPillaged(row.Hash)) and bCanProduce then
			local isCanStart, results			 = buildQueue:CanProduce( row.Hash, false, true );
			local isDisabled			:boolean = not isCanStart;

			-- Did it fail and it is a Wonder?  If so, if it failed because of *just* NO_SUITABLE_LOCATION, we can look for an alternate.
			if (isDisabled and row.IsWonder and results ~= nil and results[CityOperationResults.NO_SUITABLE_LOCATION] ~= nil and results[CityOperationResults.NO_SUITABLE_LOCATION] == true) then
				local pPurchaseablePlots :table = GetCityRelatedPlotIndexesWondersAlternative( pSelectedCity, row.Hash );
				if (pPurchaseablePlots and #pPurchaseablePlots > 0) then
					isDisabled = false;
				end
			end

			local allReasons			 :string = ComposeFailureReasonStrings( isDisabled, results );
			local sToolTip 				 :string = ToolTipHelper.GetBuildingToolTip( row.Hash, playerID, pSelectedCity ) .. allReasons;

			local iProductionCost		:number = buildQueue:GetBuildingCost( row.Index );
			local iProductionProgress	:number = buildQueue:GetBuildingProgress( row.Index );
			sToolTip = sToolTip .. "[NEWLINE][NEWLINE]";
			sToolTip = sToolTip .. ComposeProductionCostString( iProductionProgress, iProductionCost);

			local iMaintenanceCost		:number = row.Maintenance or 0;
			if (iMaintenanceCost ~= nil and iMaintenanceCost > 0) then
				local yield = GameInfo.Yields["YIELD_GOLD"];
				if(yield) then
					sToolTip = sToolTip .. "[NEWLINE]" .. Locale.Lookup("LOC_TOOLTIP_MAINTENANCE", iMaintenanceCost, yield.IconString, yield.Name);
				end
			end

			sToolTip = sToolTip .. "[NEWLINE]" .. AddBuildingExtraCostTooltip(row.Hash);
				
			table.insert( new_data.BuildingItems, {
				Type			= row.BuildingType, 
				Name			= row.Name, 
				ToolTip			= sToolTip, 
				Hash			= row.Hash, 
				Kind			= row.Kind, 
				TurnsLeft		= buildQueue:GetTurnsLeft( row.Hash ), 
				Disabled		= isDisabled, 
				Repair			= cityBuildings:IsPillaged( row.Hash ), 
				Cost			= iProductionCost, 
				Progress		= iProductionProgress, 
				IsWonder		= row.IsWonder,
				PrereqDistrict	= iPrereqDistrict,
				PrereqBuildings	= row.PrereqBuildingCollection
			});
		end
			
		-- Can it be purchased with gold?
		if row.PurchaseYield == "YIELD_GOLD" then
			local isAllowed, kBldg = ComposeBldgForPurchase( row, pSelectedCity, "YIELD_GOLD", playerTreasury, "LOC_BUILDING_INSUFFICIENT_FUNDS" );
			if isAllowed then
				table.insert( new_data.BuildingPurchases, kBldg );
			end
		end
		-- Can it be purchased with faith?
		if row.PurchaseYield == "YIELD_FAITH" or cityGold:IsBuildingFaithPurchaseEnabled( row.Hash ) then
			local isAllowed, kBldg = ComposeBldgForPurchase( row, pSelectedCity, "YIELD_FAITH", playerReligion, "LOC_BUILDING_INSUFFICIENT_FAITH" );
			if isAllowed then
				table.insert( new_data.BuildingPurchases, kBldg );
			end
		end
		
		--if GameConfiguration.IsPlayByCloud() or GameConfiguration.IsHotSeat() then
		

		
			-- Jesuit Education
			local m_pGameReligion:table = Game.GetReligion();
			local religions = m_pGameReligion:GetReligions();
			local hasJ = false
			for _, religion in ipairs(religions) do
				if (religion.Founder == playerID) then
					for b, beliefIndex in ipairs(religion.Beliefs) do
						belief = GameInfo.Beliefs[beliefIndex];
						if belief.Name == "LOC_BELIEF_JESUIT_EDUCATION_NAME" then
							hasJ = true
						end
					end
				end
			end
			
			if hasJ == true and row.IsWonder ~= true and
				(row.Name == "LOC_BUILDING_LIBRARY_NAME"
				or row.Name == "LOC_BUILDING_UNIVERSITY_NAME"
				or row.Name == "LOC_BUILDING_RESEARCH_LAB_NAME"
				or row.Name == "LOC_BUILDING_AMPHITHEATER_NAME"
				or row.Name == "LOC_BUILDING_MUSEUM_ART_NAME"
				or row.Name == "LOC_BUILDING_BROADCAST_CENTER_NAME"
				or row.Name == "LOC_BUILDING_MUSEUM_ARTIFACT_NAME" )then
				local isAllowed, kBldg = ComposeBldgForPurchase( row, pSelectedCity, "YIELD_FAITH", playerReligion, "LOC_BUILDING_INSUFFICIENT_FAITH" );
				if isAllowed then
					table.insert( new_data.BuildingPurchases, kBldg );
				end
			end	
			-- valetta
			local hasV = false
			for _, minorID in ipairs(PlayerManager.GetAliveMinorIDs()) do
				local minorP = Players[minorID]
				if minorP ~= nil then
					if PlayerConfigurations[minorID]:GetCivilizationTypeName() == "CIVILIZATION_VALLETTA" then			
						local pPlayerInfluence = minorP:GetInfluence()
						if pPlayerInfluence ~= nil then
							local suzerainID = pPlayerInfluence:GetSuzerain();
							if suzerainID == playerID then
								hasV = true
							end
						end
					end
				end
			end		
			
			if hasV == true and row.IsWonder ~= true and (
				(row.Name == "LOC_BUILDING_MONUMENT_NAME"
				or row.Name == "LOC_BUILDING_BARRACKS_NAME"
				or row.Name == "LOC_BUILDING_GRANARY_NAME"
				or row.Name == "LOC_BUILDING_WALLS_NAME"
				or row.Name == "LOC_BUILDING_WATER_MILL_NAME"
				or row.Name == "LOC_BUILDING_CASTLE_NAME"
				or row.Name == "LOC_BUILDING_SEWER_NAME"
				or row.Name == "LOC_BUILDING_STABLE_NAME"
				or row.Name == "LOC_BUILDING_MILITARY_ACADEMY_NAME"
				or row.Name == "LOC_BUILDING_ARMORY_NAME" )) then
				local isAllowed, kBldg = ComposeBldgForPurchase( row, pSelectedCity, "YIELD_FAITH", playerReligion, "LOC_BUILDING_INSUFFICIENT_FAITH" );
				if isAllowed then
					print(row.Name)
					table.insert( new_data.BuildingPurchases, kBldg );
				end
			end	

			if PlayerConfigurations[playerID]:GetCivilizationTypeName() == "CIVILIZATION_MALI" and (
				(row.Name == "LOC_BUILDING_STOCK_EXCHANGE_NAME"
				or row.Name == "LOC_BUILDING_MARKET_NAME"
				or row.Name == "LOC_BUILDING_BANK_NAME" )) then
				local isAllowed, kBldg = ComposeBldgForPurchase( row, pSelectedCity, "YIELD_FAITH", playerReligion, "LOC_BUILDING_INSUFFICIENT_FAITH" );
				if isAllowed then
					print(row.Name)
					table.insert( new_data.BuildingPurchases, kBldg );
				end
			end				
			

		--end
	end

	-- Sort BuildingItems to ensure Buildings are placed behind any Prereqs for that building
	table.sort(new_data.BuildingItems, 
		function(a, b)
			if a.IsWonder then
				return false;
			end
			if a.Disabled == false and b.Disabled == true then
				return true;
			end
			return false;
		end
	);
	

	for row in GameInfo.Units() do
		if row.Hash == m_CurrentProductionHash then
			new_data.CurrentProduction = row.Name;
			new_data.CurrentProductionType= row.UnitType;
		end

		local kBuildParameters = {};
		kBuildParameters.UnitType = row.Hash;
		kBuildParameters.MilitaryFormationType = MilitaryFormationTypes.STANDARD_MILITARY_FORMATION;

		-- Can it be built normally?
		if not row.MustPurchase and buildQueue:CanProduce( kBuildParameters, true ) then
			local isCanProduceExclusion, results	 = buildQueue:CanProduce( kBuildParameters, false, true );
			local nProductionCost		:number = buildQueue:GetUnitCost( row.Index );
			local nProductionProgress	:number = buildQueue:GetUnitProgress( row.Index );
			local isDisabled				:boolean = not isCanProduceExclusion;
			local sAllReasons				 :string = ComposeFailureReasonStrings( isDisabled, results );
			local sToolTip					 :string = ToolTipHelper.GetUnitToolTip( row.Hash, MilitaryFormationTypes.STANDARD_MILITARY_FORMATION, buildQueue ) .. sAllReasons;
				
			local kUnit :table = {
				Type				= row.UnitType, 
				Name				= row.Name, 
				ToolTip				= sToolTip, 
				Hash				= row.Hash, 
				Kind				= row.Kind, 
				TurnsLeft			= buildQueue:GetTurnsLeft( row.Hash ), 
				Disabled			= isDisabled, 
				Civilian			= row.FormationClass == "FORMATION_CLASS_CIVILIAN",
				Cost				= nProductionCost, 
				Progress			= nProductionProgress, 
				Corps				= false,
				CorpsCost			= 0,
				CorpsTurnsLeft		= 1,
				CorpsTooltip		= "",
				CorpsName			= "",
				Army				= false,
				ArmyCost			= 0,
				ArmyTurnsLeft		= 1,
				ArmyTooltip			= "",
				ArmyName			= "",
				ReligiousStrength	= row.ReligiousStrength,
				IsCurrentProduction = row.Hash == m_CurrentProductionHash
			};
				
			-- Should we present options for building Corps or Army versions?
			if results ~= nil then
				if results[CityOperationResults.CAN_TRAIN_CORPS] then
					kBuildParameters.MilitaryFormationType = MilitaryFormationTypes.CORPS_MILITARY_FORMATION;
					local bCanProduceCorps, kResults = buildQueue:CanProduce( kBuildParameters, false, true);
					kUnit.Corps			= true;
					kUnit.CorpsDisabled = not bCanProduceCorps;
					kUnit.CorpsCost		= buildQueue:GetUnitCorpsCost( row.Index );
					kUnit.CorpsTurnsLeft	= buildQueue:GetTurnsLeft( row.Hash, MilitaryFormationTypes.CORPS_MILITARY_FORMATION );
					kUnit.CorpsTooltip, kUnit.CorpsName = ComposeUnitCorpsStrings( row, nProductionProgress, buildQueue );
					local sFailureReasons:string = ComposeFailureReasonStrings( kUnit.CorpsDisabled, kResults );
					kUnit.CorpsTooltip = kUnit.CorpsTooltip .. sFailureReasons;
					kUnit.Cost= kUnit.CorpsCost;
				end
				if results[CityOperationResults.CAN_TRAIN_ARMY] then
					kBuildParameters.MilitaryFormationType = MilitaryFormationTypes.ARMY_MILITARY_FORMATION;
					local bCanProduceArmy, kResults = buildQueue:CanProduce( kBuildParameters, false, true );
					kUnit.Army			= true;
					kUnit.ArmyDisabled	= not bCanProduceArmy;
					kUnit.ArmyCost		= buildQueue:GetUnitArmyCost( row.Index );
					kUnit.ArmyTurnsLeft	= buildQueue:GetTurnsLeft( row.Hash, MilitaryFormationTypes.ARMY_MILITARY_FORMATION );
					kUnit.ArmyTooltip, kUnit.ArmyName = ComposeUnitArmyStrings( row, nProductionProgress, buildQueue );		
					local sFailureReasons:string = ComposeFailureReasonStrings( kUnit.ArmyDisabled, kResults );
					kUnit.ArmyTooltip = kUnit.ArmyTooltip .. sFailureReasons;
					kUnit.Cost = kUnit.CorpsCost;
				end
			end
				
			table.insert(new_data.UnitItems, kUnit );
		end
		
		-- Can it be purchased with gold?
		if row.PurchaseYield == "YIELD_GOLD" then
			local isAllowed, kUnit = ComposeUnitForPurchase( row, pSelectedCity, "YIELD_GOLD", playerTreasury, "LOC_BUILDING_INSUFFICIENT_FUNDS" );
			if isAllowed then
				table.insert( new_data.UnitPurchases, kUnit );
			end
		end
		-- Can it be purchased with faith?
		if row.PurchaseYield == "YIELD_FAITH" or cityGold:IsUnitFaithPurchaseEnabled( row.Hash ) then
			local isAllowed, kUnit = ComposeUnitForPurchase( row, pSelectedCity, "YIELD_FAITH", playerReligion, "LOC_BUILDING_INSUFFICIENT_FAITH" );
			if isAllowed then
				table.insert( new_data.UnitPurchases, kUnit );
			end
		end 
		
		--if GameConfiguration.IsPlayByCloud() or GameConfiguration.IsHotSeat() then

			-- Norway Berserker
			if row.Name == "LOC_UNIT_NORWEGIAN_BERSERKER_NAME" and PlayerConfigurations[playerID]:GetCivilizationTypeName() == "CIVILIZATION_NORWAY" then
				local isAllowed, kUnit = ComposeUnitForPurchase( row, pSelectedCity, "YIELD_FAITH", playerReligion, "LOC_BUILDING_INSUFFICIENT_FAITH" );
				if isAllowed then
					table.insert( new_data.UnitPurchases, kUnit );
				end			
			end
			-- Scythia
			if (row.Name == "LOC_UNIT_NORWEGIAN_BERSERKER_NAME"
				or row.Name == "LOC_UNIT_HORSEMAN_NAME"
				or row.Name == "LOC_UNIT_KNIGHT_NAME"
				or row.Name == "LOC_UNIT_COURSER_NAME"
				or row.Name == "LOC_UNIT_CUIRASSIER_NAME"
				or row.Name == "LOC_UNIT_CAVALRY_NAME"
				or row.Name == "LOC_UNIT_HEAVY_CHARIOT_NAME")
				and PlayerConfigurations[playerID]:GetCivilizationTypeName() == "CIVILIZATION_SCYTHIA" then
				local isAllowed, kUnit = ComposeUnitForPurchase( row, pSelectedCity, "YIELD_FAITH", playerReligion, "LOC_BUILDING_INSUFFICIENT_FAITH" );
				if isAllowed then
					table.insert( new_data.UnitPurchases, kUnit );
				end			
			end		
			-- Indonesia
			if (row.Name == "LOC_UNIT_INDONESIAN_JONG_NAME"
				or row.Name == "LOC_UNIT_BATTLESHIP_NAME"
				or row.Name == "LOC_UNIT_SUBMARINE_NAME"
				or row.Name == "LOC_UNIT_QUADRIREME_NAME"
				or row.Name == "LOC_UNIT_PRIVATEER_NAME"
				or row.Name == "LOC_UNIT_NUCLEAR_SUBMARINE_NAME"
				or row.Name == "LOC_UNIT_AIRCRAFT_CARRIER_NAME"
				or row.Name == "LOC_UNIT_GALLEY_NAME"
				or row.Name == "LOC_UNIT_FRIGATE_NAME"
				or row.Name == "LOC_UNIT_CARAVEL_NAME")
				and PlayerConfigurations[playerID]:GetCivilizationTypeName() == "CIVILIZATION_INDONESIA" then
				local isAllowed, kUnit = ComposeUnitForPurchase( row, pSelectedCity, "YIELD_FAITH", playerReligion, "LOC_BUILDING_INSUFFICIENT_FAITH" );
				if isAllowed then
					table.insert( new_data.UnitPurchases, kUnit );
				end			
			end	
			-- GMC -- LOC_BUILDING_GOV_FAITH_NAME
			local pPlayerCities = pPlayer:GetCities()
			local gmcType = GameInfo.Buildings["BUILDING_GOV_FAITH"].Index
			local hasGMC = false
			for _, city in pPlayerCities:Members() do
				local pBuildings = city:GetBuildings()
				if pBuildings ~= nil then
					if pBuildings:HasBuilding(gmcType) then
						hasGMC = true
						break
					end
				end
			end
			if hasGMC == true and 
				( row.Name == "LOC_UNIT_HORSEMAN_NAME"
				or row.Name == "LOC_UNIT_KNIGHT_NAME"
				or row.Name == "LOC_UNIT_COURSER_NAME"
				or row.Name == "LOC_UNIT_CUIRASSIER_NAME"
				or row.Name == "LOC_UNIT_CAVALRY_NAME"
				or row.Name == "LOC_UNIT_HEAVY_CHARIOT_NAME"
				or row.Name == "LOC_UNIT_SWORDSMAN_NAME"
				or row.Name == "LOC_UNIT_GREEK_HOPLITE_NAME"
				or row.Name == "LOC_UNIT_JAPANESE_SAMURAI_NAME"
				or row.Name == "LOC_UNIT_INDIAN_VARU_NAME"
				or row.Name == "LOC_UNIT_ARABIAN_MAMLUK_NAME"
				or row.Name == "LOC_UNIT_CROSSBOWMAN_NAME"
				or row.Name == "LOC_UNIT_CHINESE_CROUCHING_TIGER_NAME"
				or row.Name == "LOC_UNIT_PIKEMAN_NAME"
				or row.Name == "LOC_UNIT_MUSKETMAN_NAME"
				or row.Name == "LOC_UNIT_SPANISH_CONQUISTADOR_NAME"
				or row.Name == "LOC_UNIT_BOMBARD_NAME"
				or row.Name == "LOC_UNIT_FIELD_CANNON_NAME"
				or row.Name == "LOC_UNIT_RUSSIAN_COSSACK_NAME"
				or row.Name == "LOC_UNIT_ENGLISH_REDCOAT_NAME"
				or row.Name == "LOC_UNIT_FRENCH_GARDE_IMPERIALE_NAME"
				or row.Name == "LOC_UNIT_AMERICAN_ROUGH_RIDER_NAME"			
				or row.Name == "LOC_UNIT_INFANTRY_NAME"
				or row.Name == "LOC_UNIT_ARTILLERY_NAME"
				or row.Name == "LOC_UNIT_AT_CREW_NAME"
				or row.Name == "LOC_UNIT_TANK_NAME"
				or row.Name == "LOC_UNIT_MACHINE_GUN_NAME"	
				or row.Name == "LOC_UNIT_MECHANIZED_INFANTRY_NAME"
				or row.Name == "LOC_UNIT_MODERN_AT_NAME"
				or row.Name == "LOC_UNIT_MODERN_ARMOR_NAME"
				or row.Name == "LOC_UNIT_AZTEC_EAGLE_WARRIOR_NAME"
				or row.Name == "LOC_UNIT_POLISH_HUSSAR_NAME"	
				or row.Name == "LOC_UNIT_PIKE_AND_SHOT_NAME"
				or row.Name == "LOC_UNIT_SPEC_OPS_NAME"
				or row.Name == "LOC_UNIT_MAPUCHE_MALON_RAIDER_NAME"
				or row.Name == "LOC_UNIT_GIANT_DEATH_ROBOT_NAME"					
				) then
				local isAllowed, kUnit = ComposeUnitForPurchase( row, pSelectedCity, "YIELD_FAITH", playerReligion, "LOC_BUILDING_INSUFFICIENT_FAITH" );
				if isAllowed then
					table.insert( new_data.UnitPurchases, kUnit );
				end				
			end
			-- Monumentality
			local pGameEras:table = Game.GetEras();
			local activeCommemorations = pGameEras:GetPlayerActiveCommemorations(playerID)
			local hasM = false
			for i,activeCommemoration in ipairs(activeCommemorations) do
				local commemorationInfo = GameInfo.CommemorationTypes[activeCommemoration];
				if (commemorationInfo ~= nil) then
					if commemorationInfo.GoldenAgeBonusDescription == "LOC_MOMENT_CATEGORY_INFRASTRUCTURE_BONUS_GOLDEN_AGE" then
						hasM = true
						break
					end
				end
			end
			if (row.Name == "LOC_UNIT_SETTLER_NAME" or row.Name == "LOC_UNIT_BUILDER_NAME" or row.Name == "LOC_UNIT_TRADER_NAME")and hasM == true then
				local isAllowed, kUnit = ComposeUnitForPurchase( row, pSelectedCity, "YIELD_FAITH", playerReligion, "LOC_BUILDING_INSUFFICIENT_FAITH" );
				if isAllowed then
					table.insert( new_data.UnitPurchases, kUnit );
				end			
			end
		--end
	end
	
	
	if (pBuildQueue == nil) then
		pBuildQueue = pSelectedCity:GetBuildQueue();
	end

	for row in GameInfo.Projects() do
		if row.Hash == m_CurrentProductionHash then
			new_data.CurrentProduction = row.Name;
			new_data.CurrentProductionType= row.ProjectType;
		end

		if buildQueue:CanProduce( row.Hash, true ) then
			local isCanProduceExclusion, results = buildQueue:CanProduce( row.Hash, false, true );
			local isDisabled			:boolean = not isCanProduceExclusion;
				
			local allReasons		:string	= ComposeFailureReasonStrings( isDisabled, results );
			local sToolTip			:string = ToolTipHelper.GetProjectToolTip( row.Hash) .. allReasons;
				
			local iProductionCost		:number = buildQueue:GetProjectCost( row.Index );
			local iProductionProgress	:number = buildQueue:GetProjectProgress( row.Index );
			sToolTip = sToolTip .. "[NEWLINE]" .. ComposeProductionCostString( iProductionProgress, iProductionCost );
				
			table.insert(new_data.ProjectItems, {
				Type				= row.ProjectType,
				Name				= row.Name, 
				ToolTip				= sToolTip, 
				Hash				= row.Hash, 
				Kind				= row.Kind, 
				TurnsLeft			= buildQueue:GetTurnsLeft( row.ProjectType ), 
				Disabled			= isDisabled, 
				Cost				= iProductionCost, 
				Progress			= iProductionProgress,
				IsCurrentProduction = row.Hash == m_CurrentProductionHash,
				IsRepeatable		= row.MaxPlayerInstances ~= 1 and true or false,
			});
		end
	end
	


	return new_data;
end

