local apiarySide = "left"
local chestSide = "top"
local chestDir = "up"
local analyzerDir = "east"

local traitPriority = {"speciesChance", "fertility", "speed", "nocturnal", "tolerantFlyer", "caveDwelling", "lifespan", "temperatureTolerance", "humidityTolerance", "effect", "flowering", "flowerProvider", "territory"}

local inv = peripheral.wrap(chestSide)
local invSize = inv.getInventorySize()

local apiary = peripheral.wrap(apiarySide)

local princesses = {}
local princessesBySpecies = {}
local drones = {}
local dronesBySpecies = {}
local queens = {}

-- utility functions

function choose(list1, list2)
  local newList = {}
  if list2 then
    for i = 1, #list2 do
      for j = 1, #list1 do
        if list1[j] ~= list2[i] then
          table.insert(newList, {list1[j], list2[i]})
        end
      end
    end
  else
    for i = 1, #list1 do
      for j = i, #list1 do
        if list1[i] ~= list1[j] then
          table.insert(newList, {list1[i], list1[j]})
        end
      end
    end
  end
  return newList
end

-- mutation graph

local mutations = {}

function addMutateTo(parent1, parent2, offspring, chance, specialConditions)
  if mutations[parent1] then
    if mutations[parent1].mutateTo[offspring] then
      mutations[parent1].mutateTo[offspring][parent2] = chance
    else
      mutations[parent1].mutateTo[offspring] = {[parent2] = chance}
    end
  else
    mutations[parent1] = {
      mutateTo = {[offspring]={[parent2] = chance}},
      mutateFrom = {},
      specialConditions = {}
    }
  end
  if mutations[offspring] then
    table.insert(mutations[offspring].mutateFrom, {parent1, parent2})
    mutations[offspring].specialConditions = specialConditions
  else
    mutations[offspring] = {mutateFrom = {{parent1, parent2}},
                            mutateTo = {},
                            specialConditions = specialConditions}
  end
end

function addOffspring(offspring, chance, parentss)
  for i, parents in ipairs(parentss) do
    addMutateTo(parents[1], parents[2], offspring, chance)
    addMutateTo(parents[2], parents[1], offspring, chance)
  end
end

-- build mutation graph
for _, mut in pairs(apiary.getBeeBreedingData()) do
  addMutateTo(mut.allele1, mut.allele2, mut.result, mut.chance, mut.specialConditions)
  addMutateTo(mut.allele2, mut.allele1, mut.result, mut.chance, mut.specialConditions)
end

function addBySpecies(beesBySpecies, bee)
  if beesBySpecies[bee.beeInfo.active.species] == nil then
    beesBySpecies[bee.beeInfo.active.species] = {bee}
  else
    table.insert(beesBySpecies[bee.beeInfo.active.species], bee)
  end
  if bee.beeInfo.inactive.species ~= bee.beeInfo.active.species then
    if beesBySpecies[bee.beeInfo.inactive.species] == nil then
      beesBySpecies[bee.beeInfo.inactive.species] = {bee}
    else
      table.insert(beesBySpecies[bee.beeInfo.inactive.species], bee)
    end
  end
end

function catalogBees()
  princesses = {}
  princessesBySpecies = {}
  drones = {}
  dronesBySpecies = {}
  queens = {}
  inv.condenseItems()
  print(string.format("scanning %d slots", invSize))
  for slot = 1, invSize do
    local bee = inv.getStackInSlot(slot)
    if bee ~= nil then
      if bee.beeInfo ~= nil and bee.beeInfo.isAnalyzed == false then
        analyzeBee(slot)
        bee = inv.getStackInSlot(slot)
      end
      bee.slot = slot
      if bee.rawName == "item.beedronege" then -- drones
        table.insert(drones, bee)
        addBySpecies(dronesBySpecies, bee)
      elseif bee.rawName == "item.beeprincessge" then -- princess
        table.insert(princesses, bee)
        addBySpecies(princessesBySpecies, bee)
      elseif bee.id == 13339 then -- queens
        table.insert(queens, bee)
      end
    end
  end
  print(string.format("found %d queens, %d princesses, %d drones",
      #queens, #princesses, #drones))
end

-- apiary functions

function clearApiary()
  local beeCount = 0
  local invSlot = 1
  for slot = 3, 9 do
    local stuff = apiary.getStackInSlot(slot)
    if stuff ~= nil then
      while inv.getStackInSlot(invSlot) ~= nil do
        invSlot = invSlot + 1
      end
      if stuff.rawName == "item.beedronege" or stuff.rawName == "item.beeprincessge" then
        beeCount = beeCount + 1
        apiary.pushItem(chestDir, slot, 64, invSlot)
      else
        local found = false
        local freeSlot = 0
        for productSlot = 1, invSize do
          local item = inv.getStackInSlot(productSlot)
          if item == nil then
            freeSlot = productSlot
          elseif stuff.name == item.name and (item.maxSize - item.qty) >= stuff.qty then
            apiary.pushItem(chestDir, slot, 64, productSlot)
            found = true
            break
          end
        end
        if not found then
          apiary.pushItem(chestDir, slot, 64, freeSlot)
        end
      end
    end
  end
  return beeCount
end

function clearAnalyzer()
  local invSlot = 1
  for analyzerSlot = 9, 12 do
    while inv.getStackInSlot(invSlot) ~= nil do
      invSlot = invSlot + 1
      if invSlot > invSize then
        error("chest is full")
      end
    end
    inv.pullItem(analyzerDir, analyzerSlot, 64, invSlot)
  end
end

function analyzeBee(slot)
  clearAnalyzer()
  write("analyzing bee ")
  write(slot)
  inv.pushItem(analyzerDir, slot, 64, 3)
  while inv.pullItem(analyzerDir, 9, 64, slot) == 0 do
    sleep(1)
    write(".")
  end
  print()
  printBee(inv.getStackInSlot(slot))
end

function waitApiary()
  write("waiting for apiary")
  while apiary.getStackInSlot(1) ~= nil or apiary.getStackInSlot(2) ~= nil do
    write(".")
    sleep(5)
    if clearApiary() > 0 then
      -- breeding cycle done
      break
    end
  end
  clearApiary()
  print()
end

function breedBees(princess, drone)
  clearApiary()
  waitApiary()
  apiary.pullItem(chestDir, princess.slot, 1, 1)
  apiary.pullItem(chestDir, drone.slot, 1, 2)
  waitApiary()
end

-- scoring functions

function canMutateTo(bee, targetSpecies)
  if bee.beeInfo.active then
    if (bee.beeInfo.active.species == targetSpecies
            or mutations[bee.beeInfo.active.species].mutateTo[targetSpecies] ~= nil) then
      return bee.beeInfo.active.species
    elseif (bee.beeInfo.inactive.species == targetSpecies
            or mutations[bee.beeInfo.inactive.species].mutateTo[targetSpecies] ~= nil) then
      return bee.beeInfo.inactive.species
    end
  else
    if (bee.beeInfo.displayName == targetSpecies
            or mutations[bee.beeInfo.displayName].mutateTo[targetSpecies] ~= nil) then
      return bee.beeInfo.displayName
    end
  end
end

-- percent chance of 2 species turning into a target species
function mutationChance(species1, species2, targetSpecies)
  local chance = {}
  if species1 == species2 then
    chance[species1] = 100
  else
    chance[species1] = 50
    chance[species2] = 50
  end
  for species, mutates in pairs(mutations[species1].mutateTo) do
    local mutateChance = mutates[species2]
    if mutateChance ~= nil then
      chance[species] = mutateChance
      chance[species1] = chance[species1] - mutateChance / 2
      chance[species2] = chance[species2] - mutateChance / 2
    end
  end
  return chance[targetSpecies] or 0.0
end

-- percent chance of 2 bees turning into target species
function mutateChance(princess, drone, targetSpecies)
  if princess.beeInfo.active then
    if drone.beeInfo.active then
      return (mutationChance(princess.beeInfo.active.species, drone.beeInfo.active.species, targetSpecies) / 4
             +mutationChance(princess.beeInfo.inactive.species, drone.beeInfo.active.species, targetSpecies) / 4
             +mutationChance(princess.beeInfo.active.species, drone.beeInfo.inactive.species, targetSpecies) / 4
             +mutationChance(princess.beeInfo.inactive.species, drone.beeInfo.inactive.species, targetSpecies) / 4)
    end
  elseif drone.beeInfo.active then
  else
    return mutationChance(princess.beeInfo.displayName, drone.beeInfo.displayName, targetSpecies)
  end
end

function beeName(bee)
  if bee.beeInfo.active then
    return bee.slot .. "=" .. bee.beeInfo.active.species:sub(1,3) .. "-" ..
                              bee.beeInfo.inactive.species:sub(1,3)
  else
    return bee.slot .. "=" .. bee.beeInfo.displayName:sub(1,3)
  end
end

function printBee(bee)
  if bee.beeInfo.active then
    local active = bee.beeInfo.active
    local inactive = bee.beeInfo.inactive
    if active.species ~= inactive.species then
      write(string.format("%s-%s", active.species, inactive.species))
    else
      write(active.species)
    end
    if bee.rawName == "item.beedronege" then
      write(" Drone")
    elseif bee.rawName == "item.beeprincessge" then
      write(" Princess")
    else
      write(" Queen")
    end
    write((active.nocturnal and " Nocturnal" or " "))
    write((active.tolerantFlyer and " Flyer" or " "))
    write((active.caveDwelling and " Cave" or " "))
    print()
    print(string.format("Fert: %d  Speed: %d  Lifespan: %d", active.fertility, active.speed, active.lifespan))
  else
  end
end

function makeNumberScorer(trait, default)
  local function scorer(bee1, bee2)
    local bee1score = default
    local bee2score = default
    if bee1.beeInfo.active then
      bee1score = (bee1.beeInfo.active[trait] + bee1.beeInfo.inactive[trait]) / 2
    end
    if bee2.beeInfo.active then
      bee2score = (bee2.beeInfo.active[trait] + bee2.beeInfo.inactive[trait]) / 2
    end
    return (bee1score + bee2score) / 2
  end
  return scorer
end

function makeBooleanScorer(trait)
  local function scorer(bee1, bee2)
    local score = 0
    if bee1.beeInfo.active then
      score = score + (bee1.beeInfo.active[trait] and 1 or 0) + (bee1.beeInfo.inactive[trait] and 1 or 0)
    end
    if bee2.beeInfo.active then
      score = score + (bee2.beeInfo.active[trait] and 1 or 0) + (bee2.beeInfo.inactive[trait] and 1 or 0)
    end
    return score
  end
  return scorer
end

function makeTableScorer(trait, default, lookup)
  local function scorer(bee1, bee2)
    local bee1score = default
    local bee2score = default
    if bee1.beeInfo.active then
      bee1score = (lookup[bee1.beeInfo.active[trait]] + lookup[bee1.beeInfo.inactive[trait]]) / 2
    end
    if bee2.beeInfo.active then
      bee2score = (lookup[bee2.beeInfo.active[trait]] + lookup[bee2.beeInfo.inactive[trait]]) / 2
    end
    return (bee1score + bee2score) / 2
  end
  return scorer
end

local scoresTolerance = {
  ["None"]   = 0,
  ["Up 1"]   = 1,
  ["Up 2"]   = 2,
  ["Up 3"]   = 3,
  ["Up 4"]   = 4,
  ["Up 5"]   = 5,
  ["Down 1"] = 1,
  ["Down 2"] = 2,
  ["Down 3"] = 3,
  ["Down 4"] = 4,
  ["Down 5"] = 5,
  ["Both 1"] = 2,
  ["Both 2"] = 4,
  ["Both 3"] = 6,
  ["Both 4"] = 8,
  ["Both 5"] = 10
}

local scoresFlowerProvider = {
  ["None"] = 5,
  ["Rock"] = 4,
  ["Flowers"] = 3,
  ["Mushroom"] = 2,
  ["Cacti"] = 1
}

local scoreFertility = makeNumberScorer("fertility", 1)
local scoreFlowering = makeNumberScorer("flowering", 0)
local scoreSpeed = makeNumberScorer("speed")
local scoreLifespawn = makeNumberScorer("lifespan", 20)
local scoreNocturnal = makeBooleanScorer("nocturnal")
local scoreTolerantFlyer = makeBooleanScorer("tolerantFlyer")
local scoreCaveDweling = makeBooleanScorer("caveDwelling")
local scoreEffect = makeBooleanScorer("effect")
local scoreTemperatureTolerance =  makeTableScorer("temperatureTolerance", 0, scoresTolerance)
local scoreHumidityTolerance = makeTableScorer("humidityTolerance", 0, scoresTolerance)
local scoreFlowerProvider = makeTableScorer("flowerProvider", 0, scoresFlowerProvider)
local scoreTerritory = function(bee1, bee2)
  local bee1score = 0
  local bee2score = 0
  if bee1.beeInfo.active then
    bee1score = ((bee1.beeInfo.active.territory[1] * bee1.beeInfo.active.territory[2] * bee1.beeInfo.active.territory[3]) +
                 (bee1.beeInfo.inactive.territory[1] * bee1.beeInfo.inactive.territory[2] * bee1.beeInfo.inactive.territory[3])) / 2
  end
  if bee2.beeInfo.active then
    bee2score = ((bee2.beeInfo.active.territory[1] * bee2.beeInfo.active.territory[2] * bee2.beeInfo.active.territory[3]) +
                 (bee2.beeInfo.inactive.territory[1] * bee2.beeInfo.inactive.territory[2] * bee2.beeInfo.inactive.territory[3])) / 2
  end
  return (bee1score + bee2score) / 2
end

function compareMates(a, b)
  for i, trait in ipairs(traitPriority) do
    if a[trait] ~= b[trait] then
      return a[trait] > b[trait]
    end
  end
  return true
end

function getMate(beeSpecies, targetSpecies)
  for i, parents in ipairs(mutations[targetSpecies].mutateFrom) do
    if beeSpecies == parents[1] then
      return parents[2]
    end
  end
end

-- selects best pair for target species
--   or initiates breeding of lower species
function selectPair(targetSpecies)
  print("targetting "..targetSpecies)
  for _, s in ipairs(mutations[targetSpecies].specialConditions) do
    print("    ", s)
  end
  local mateCombos = choose(princesses, drones)
  local mates = {}
  for i, v in ipairs(mateCombos) do
    local chance = mutateChance(v[1], v[2], targetSpecies)
    if chance > 0 then
      table.insert(mates, {
        ["princess"] = v[1],
        ["drone"] = v[2],
        ["speciesChance"] = mutateChance(v[1], v[2], targetSpecies),
        ["fertility"] = scoreFertility(v[1], v[2]),
        ["flowering"] = scoreFlowering(v[1], v[2]),
        ["speed"] = scoreSpeed(v[1], v[2]),
        ["lifespan"] = scoreLifespawn(v[1], v[2]),
        ["nocturnal"] = scoreNocturnal(v[1], v[2]),
        ["tolerantFlyer"] = scoreTolerantFlyer(v[1], v[2]),
        ["caveDwelling"] = scoreCaveDweling(v[1], v[2]),
        ["effect"] = scoreEffect(v[1], v[2]),
        ["temperatureTolerance"] = scoreTemperatureTolerance(v[1], v[2]),
        ["humidityTolerance"] = scoreHumidityTolerance(v[1], v[2]),
        ["flowerProvider"] = scoreFlowerProvider(v[1], v[2]),
        ["territory"] = scoreTerritory(v[1], v[2]),
      })
    end
  end
  if #mates > 0 then
    table.sort(mates, compareMates)
    for i = math.min(#mates, 10), 1, -1 do
      local parents = mates[i]
      print(beeName(parents.princess), " ", beeName(parents.drone), " ", parents.speciesChance, " ", parents.fertility, " ",
            parents.flowering, " ", parents.nocturnal, " ", parents.tolerantFlyer, " ", parents.caveDwelling, " ",
            parents.lifespan, " ", parents.temperatureTolerance, " ", parents.humidityTolerance)
    end
    return mates[1]
  else
    -- attempt lower tier bee
    print("try lower tier of "..targetSpecies)
    local parentss = apiary.getBeeParents(targetSpecies)
    if #parentss > 0 then
      table.sort(parentss, function(a, b) return a.chance > b.chance end)
      local trySpecies = {}
      for i, parents in ipairs(parentss) do
        if princessesBySpecies[parents.allele2] == nil and trySpecies[parents.allele2] == nil then
          table.insert(trySpecies, parents.allele2)
          trySpecies[parents.allele2] = true
        end
        if princessesBySpecies[parents.allele1] == nil and trySpecies[parents.allele1] == nil then
          table.insert(trySpecies, parents.allele1)
          trySpecies[parents.allele1] = true
        end
      end
      for _, species in ipairs(trySpecies) do
        local mates = selectPair(species)
        if mates ~= nil then
          return mates
        end
      end
    end
    return nil
  end
end

function isPureBred(bee1, bee2, targetSpecies)
  if bee1.beeInfo.active and bee2.beeInfo.active then
    if bee1.beeInfo.active.species == bee1.beeInfo.inactive.species and
        bee2.beeInfo.active.species == bee2.beeInfo.inactive.species and
        bee1.beeInfo.active.species == bee2.beeInfo.active.species and
        (targetSpecies == nil or bee1.beeInfo.active.species == targetSpecies) then
      return true
    end
  end
  return false
end

local tArgs = { ... }
if #tArgs ~= 1 then
  print("Enter target species")
  return
end

clearApiary()
clearAnalyzer()
catalogBees()
while true do
  local mates = selectPair(tArgs[1])
  if mates ~= nil then
    if isPureBred(mates.princess, mates.drone, tArgs[1]) then
      break
    else
      breedBees(mates.princess, mates.drone)
      catalogBees()
    end
  else
    write("Please add more bees and press [Enter]")
    io.read("*l")
    catalogBees()
  end
end
print("Bees are purebred")
