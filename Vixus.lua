-- Finder Egg Vixus v1.0.0 (Clean & Redesigned Edition)
-- Fully customized UI and streamlined codebase.

local Players = game:GetService('Players')
local RS = game:GetService('ReplicatedStorage')
local player = Players.LocalPlayer
assert(player, 'Join the game first')

local parent = player:WaitForChild('PlayerGui', 15)
assert(parent, 'PlayerGui unavailable')

local old = parent:FindFirstChild('VIXUS_EGG_FINDER')
if old then old:Destroy() end

local gui = Instance.new('ScreenGui')
gui.Name = 'VIXUS_EGG_FINDER'
gui:SetAttribute('VixusUIBuild','PRO-EDITION')
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
pcall(function() gui.ScreenInsets = Enum.ScreenInsets.None end)
pcall(function() gui.ClipToDeviceSafeArea = false end)
gui.DisplayOrder = 1200
gui.Parent = parent

local alive = true
local highlight
gui.Destroying:Connect(function() alive = false; if highlight then highlight:Destroy() end end)

local function make(class, props, holder)
    local obj = Instance.new(class)
    for key, value in pairs(props) do obj[key] = value end
    obj.Parent = holder
    return obj
end

local function label(holder, text, pos, size, color, fontSize)
    return make('TextLabel', {
        Text = text, Position = pos, Size = size, 
        BackgroundTransparency = 1, TextColor3 = color or Color3.fromRGB(240, 240, 245), 
        Font = Enum.Font.GothamBold, TextSize = fontSize or 13, 
        TextXAlignment = Enum.TextXAlignment.Left, 
        TextTruncate = Enum.TextTruncate.AtEnd
    }, holder)
end

local function module(path)
    local obj = RS
    for part in path:gmatch('[^.]+') do
        obj = obj:FindFirstChild(part)
        assert(obj, 'Missing game module: '..path)
    end
    return require(obj)
end

local function numberField(record, keys)
    for _, key in ipairs(keys) do
        local value = record and record[key]
        if type(value)=='number' and value==value and math.abs(value)<math.huge then return value end
    end
end

local function modelFor(uid)
    if type(uid)~='string' then return end
    local folder = workspace:FindFirstChild('AreaEggSlotsClient')
    local obj = (folder and folder:FindFirstChild(uid)) or workspace:FindFirstChild(uid)
    if obj and obj:IsA('Model') then return obj end
end

local function displayedRate(model)
    if not model then return end
    local powers={['']=1,k=1e3,m=1e6,b=1e9,t=1e12,qa=1e15,q=1e15,qi=1e18}
    for _,obj in ipairs(model:GetDescendants()) do
        if obj:IsA('TextLabel') or obj:IsA('TextButton') then
            local text=obj.Text:gsub('<[^>]+>',''):gsub(',','')
            local amount,suffix=text:match('%$?%s*(%d+%.?%d*)%s*(%a*)%s*/[sS]')
            local factor=suffix and powers[suffix:lower()]
            if amount and factor then return tonumber(amount)*factor end
        end
    end
end

local function money(value)
    if not value then return 'Income unavailable' end
    for _,entry in ipairs({{1e18,'Qi'},{1e15,'Qa'},{1e12,'T'},{1e9,'B'},{1e6,'M'},{1e3,'K'}}) do
        if value>=entry[1] then return string.format('$%.2f%s/s',value/entry[1],entry[2]) end
    end
    return string.format('$%.2f/s',value)
end

local function valid(value)
    return type(value)=='number' and value==value and value>=0 and value<math.huge
end

local function computedRate(base, scale, muts, mutationModule)
    if not valid(base) or not valid(scale) or scale==0 then return nil end
    local multi=1
    if type(muts)~='table' then return nil end
    if next(muts) then
        local fn=mutationModule and mutationModule.EarningsFor
        if type(fn)~='function' then return nil end
        local ok,result=pcall(fn,muts)
        if not ok or not valid(result) then return nil end
        multi=result
    end
    local factor=scale>5 and (scale/5)^1.2*19.637875755794113 or scale^1.85
    local result=base*factor*multi
    return valid(result) and result or nil
end

local function readTraitNames(record)
    local names,seen={},{}
    local known=record.Mutations~=nil or record.BaseMutation~=nil
    local function add(value)
        if type(value)=='string' and value~='' and value~='None' and value~='Normal' and not seen[value] then seen[value]=true;names[#names+1]=value end
    end
    if type(record.Mutations)=='table' then
        for key,value in pairs(record.Mutations) do
            if value==true and type(key)=='string' then add(key)
            elseif type(value)=='string' then add(value)
            elseif type(value)=='table' then local id=value.Id or value._id or value.Name; if type(id)=='string' then add(id) else known=false end end
        end
    elseif type(record.Mutations)=='string' then
        for value in record.Mutations:gmatch('[^,;|]+') do add(value:match('^%s*(.-)%s*$')) end
    end
    add(record.BaseMutation);table.sort(names)
    return names,known
end

local function createFinder(D)
    local originalMake,originalLabel=D.make,D.label
    D.make=function(class,props,parent)
        if class=='TextButton' or class=='TextBox' then props.Font=Enum.Font.GothamBold;props.TextSize=math.max(props.TextSize or 14,14) end
        local obj=originalMake(class,props,parent)
        if class=='TextButton' or class=='TextBox' then originalMake('UICorner',{CornerRadius=UDim.new(0,6)},obj) end
        return obj
    end
    D.label=function(parent,text,pos,size,color,fontSize)
        local obj=originalLabel(parent,text,pos,size,color or Color3.fromRGB(240,242,255),math.max(fontSize or 14,13))
        obj.Font=Enum.Font.GothamBold;return obj
    end

    local Http=game:GetService('HttpService')
    local Teleports=game:GetService('TeleportService')
    local requestFn=request or http_request or (syn and syn.request) or (http and http.request)
    local active,othersOnly=true,false
    local reporterId=Http:GenerateGUID(false)
    local config=nil
    local feed={}
    local clockOffset=0
    local networkBusy=false
    local networkTicket=0
    local minRate,minRank=0,6
    local queryEpoch=0

    -- Modern floating open button (VIXUS)
    local open=D.make('TextButton',{Text='VIXUS',Position=UDim2.new(0,20,0,100),Size=UDim2.fromOffset(70,70),BackgroundColor3=Color3.fromRGB(20,22,28),TextColor3=Color3.fromRGB(255,80,95),TextSize=15},D.gui)
    D.make('UICorner',{CornerRadius=UDim.new(1,0)},open)
    D.make('UIStroke',{Color=Color3.fromRGB(255,80,95),Thickness=2},open)

    -- Main UI Panel with sleek dark theme
    local panel=D.make('Frame',{AnchorPoint=Vector2.new(0,0.5),Position=UDim2.new(0,105,0.5,0),Size=UDim2.fromOffset(410,560),BackgroundColor3=Color3.fromRGB(18,19,24),Visible=false},D.gui)
    D.make('UICorner',{CornerRadius=UDim.new(0,10)},panel)
    D.make('UIStroke',{Color=Color3.fromRGB(45,48,58),Thickness=2},panel)

    -- Top bar header
    local bar=D.make('Frame',{Position=UDim2.fromOffset(0,0),Size=UDim2.new(1,0,0,50),BackgroundColor3=Color3.fromRGB(25,27,34),BorderSizePixel=0},panel)
    D.make('UICorner',{CornerRadius=UDim.new(0,10)},bar)
    -- Fix bottom corners of header bar to be square
    D.make('Frame',{Position=UDim2.new(0,0,1,-10),Size=UDim2.new(1,0,0,10),BackgroundColor3=Color3.fromRGB(25,27,34),BorderSizePixel=0},bar)

    local heading=D.label(bar,'Finder Egg Vixus',UDim2.fromOffset(16,0),UDim2.new(1,-60,1,0),Color3.fromRGB(255,255,255),18)
    
    local close=D.make('TextButton',{Text='✕',Position=UDim2.new(1,-42,0,9),Size=UDim2.fromOffset(32,32),BackgroundColor3=Color3.fromRGB(235,59,90),TextColor3=Color3.new(1,1,1),TextSize=16},bar)
    open.Activated:Connect(function() panel.Visible=not panel.Visible end)
    close.Activated:Connect(function() panel.Visible=false end)

    -- Scope Selector Buttons (All Servers vs My Server)
    local scope=D.make('TextButton',{Text='ALL SERVERS',Position=UDim2.new(0,12,1,-58),Size=UDim2.new(0.5,-18,0,40),BackgroundColor3=Color3.fromRGB(40,167,69),TextColor3=Color3.new(1,1,1),TextSize=13},panel)
    local myScope=D.make('TextButton',{Text='MY SERVER',Position=UDim2.new(0.5,6,1,-58),Size=UDim2.new(0.5,-18,0,40),BackgroundColor3=Color3.fromRGB(35,38,48),TextColor3=Color3.new(1,1,1),TextSize=13},panel)
    
    local function styleScope()
        scope.BackgroundColor3=othersOnly and Color3.fromRGB(35,38,48) or Color3.fromRGB(40,167,69)
        myScope.BackgroundColor3=othersOnly and Color3.fromRGB(40,167,69) or Color3.fromRGB(35,38,48)
    end
    
    local function setScope(myServer)
        if othersOnly==myServer then return end
        othersOnly=myServer;styleScope()
        queryEpoch+=1;feed={
            
        }
    end
    scope.Activated:Connect(function() setScope(false) end)
    myScope.Activated:Connect(function() setScope(true) end)
    styleScope()

    local rarityOptions={{name='Mythic',rank=6},{name='Cosmic',rank=7},{name='Secret',rank=8},{name='Eternal',rank=9},{name='Divine',rank=10},{name='Any',rank=0}}
    local rarityIndex=1
    for i,option in ipairs(rarityOptions) do if option.rank==minRank then rarityIndex=i;break end end

    local rarityBtn=D.make('TextButton',{Text='MIN RARITY: '..rarityOptions[rarityIndex].name,Position=UDim2.new(0,12,1,-110),Size=UDim2.new(1,-24,0,38),BackgroundColor3=Color3.fromRGB(35,92,190),TextColor3=Color3.new(1,1,1),TextSize=13},panel)
    rarityBtn.Activated:Connect(function()
        rarityIndex=rarityIndex%#rarityOptions+1;minRank=rarityOptions[rarityIndex].rank
        rarityBtn.Text='MIN RARITY: '..rarityOptions[rarityIndex].name
        queryEpoch+=1;feed={}
    end)

    local refreshButton=D.make('TextButton',{Text='REFRESH DATA',Position=UDim2.fromOffset(12,62),Size=UDim2.new(1,-24,0,34),BackgroundColor3=Color3.fromRGB(45,50,65),TextColor3=Color3.new(1,1,1),TextSize=13},panel)
    
    local list=D.make('ScrollingFrame',{Position=UDim2.fromOffset(12,106),Size=UDim2.new(1,-24,1,-230),BackgroundTransparency=1,BorderSizePixel=0,CanvasSize=UDim2.new(),ScrollBarThickness=4},panel)
    D.make('UIListLayout',{Padding=UDim.new(0,6),SortOrder=Enum.SortOrder.LayoutOrder},list)

    local function network(url,method,body,headers)
        if type(requestFn)~='function' then return nil end
        if networkBusy then return nil end
        networkBusy=true
        networkTicket+=1
        local ticket=networkTicket
        local done,result=false,nil
        task.spawn(function()
            result=table.pack(pcall(requestFn,{Url=url,Method=method,Headers=headers or {},Body=body,Timeout=10}))
            done=true; if networkTicket==ticket then networkBusy=false end
        end)
        local deadline=os.clock()+12
        while active and not done and os.clock()<deadline do task.wait(0.1) end
        if not done or not result[1] or result[2].StatusCode~=200 then return nil end
        local ok,decoded=pcall(Http.JSONDecode,Http,result[2].Body or '')
        return ok and decoded or nil
    end

    local function loadConfig()
        local data=network('https://raw.githubusercontent.com/cacacuco107-ops/Vixus/main/NYX-Finder-Config.json?v='..os.time(),'GET')
        if data then config=data end
    end

    local function snapshot()
        local eggs={}
        for _,entry in ipairs(D.entries()) do
            if not entry.unresolved and entry.uid and entry.rate and entry.rate>0 then
                eggs[#eggs+1]={uid=tostring(entry.uid),name=entry.name,category=entry.category,rarity=entry.rarity,rank=entry.tier,rate=entry.rate,scale=entry.scale,weight=entry.weight,icon=entry.icon,area=entry.areaKey or entry.area,mutations=entry.mutationText or '',traitsKnown=entry.traitsKnown~=false,estimated=entry.estimated==true,source=entry.isEvent and 'event' or 'field'}
            end
        end
        table.sort(eggs,function(a,b) return a.rate>b.rate end)
        while #eggs>10 do eggs[#eggs]=nil end
        return eggs
    end

    local function report()
        if game.JobId=='' or not D.ready() or not config then return end
        local eggs=snapshot()
        local body={placeId=game.PlaceId,jobId=game.JobId,reporterId=reporterId,eggs=eggs}
        network(config.endpoint..'/v1/report','POST',Http:JSONEncode(body),{['Content-Type']='application/json',['X-NYX-Room']=config.roomKey})
    end
    D.flushReport=report

    local function refresh()
        if not config then return end
        local epoch=queryEpoch
        local query='?localJob='..Http:UrlEncode(game.JobId)..'&placeId='..game.PlaceId..'&limit=30&offset=0&minRate='..tostring(minRate)..'&minRank='..tostring(minRank)
        if othersOnly then query=query..'&onlyJob='..Http:UrlEncode(game.JobId) end
        local data=network(config.endpoint..'/v1/eggs'..query,'GET',nil,{['Content-Type']='application/json',['X-NYX-Room']=config.roomKey})
        if epoch~=queryEpoch or not data or type(data.items)~='table' then return end
        clockOffset=(tonumber(data.serverTime) or os.time()*1000)/1000-os.clock()
        feed=data.items
    end

    local function renderOnce()
        local entries={}
        local live=D.entries()
        
        if othersOnly then
            for _,e in ipairs(live) do
                if (e.rate or 0)>=minRate and (e.tier or 0)>=minRank then
                    entries[#entries+1]={
                        key=game.JobId..':'..tostring(e.uid or e.key), uid=tostring(e.uid or e.key),
                        name=e.name, rate=e.rate or 0, scale=e.scale, weight=e.weight,
                        icon=e.icon, rarity=e.rarity, rank=e.tier, mutations=e.mutationText,
                        placeId=game.PlaceId, jobId=game.JobId, isLocal=true
                    }
                end
            end
        else
            for _,e in ipairs(feed) do
                if (e.rate or 0)>=minRate and (e.rank or 0)>=minRank then
                    entries[#entries+1]=e
                end
            end
        end

        table.sort(entries,function(a,b) return (a.rate or 0) > (b.rate or 0) end)
        
        list:ClearAllChildren()
        D.make('UIListLayout',{Padding=UDim.new(0,6),SortOrder=Enum.SortOrder.LayoutOrder},list)

        for i,entry in ipairs(entries) do
            local row=D.make('Frame',{Size=UDim2.new(1,-8,0,65),LayoutOrder=i,BackgroundColor3=Color3.fromRGB(26,29,36)},list)
            D.make('UICorner',{CornerRadius=UDim.new(0,6)},row)

            if entry.icon then
                D.make('ImageLabel',{Image=entry.icon,BackgroundTransparency=1,Size=UDim2.fromOffset(45,45),Position=UDim2.fromOffset(10,10)},row)
            end

            label(row, tostring(entry.name), UDim2.fromOffset(65, 10), UDim2.new(1, -150, 0, 20), Color3.fromRGB(255,255,255), 14)
            label(row, D.money(entry.rate), UDim2.fromOffset(65, 32), UDim2.new(1, -150, 0, 18), Color3.fromRGB(46,213,115), 12)

            local join=D.make('TextButton',{Text='JOIN',Position=UDim2.new(1,-75,0,15),Size=UDim2.fromOffset(65,34),BackgroundColor3=Color3.fromRGB(40,167,69),TextColor3=Color3.new(1,1,1),TextSize=12},row)
            
            join.Activated:Connect(function()
                if entry.jobId == game.JobId then return end
                D.stopFarm()
                Teleports:TeleportToPlaceInstance(entry.placeId, entry.jobId, D.player)
            end)
        end
        list.CanvasSize=UDim2.fromOffset(0,#entries*71)
    end

    refreshButton.Activated:Connect(function()
        task.spawn(function()
            if not config then loadConfig() end
            if not othersOnly then refresh() end
            renderOnce()
        end)
    end)

    task.spawn(function()
        while active do
            pcall(function()
                if not config then loadConfig() end
                report()
                if not othersOnly then refresh() end
                renderOnce()
            end)
            task.wait(5)
        end
    end)
end

local function run()
    local EggState=module('Client.EggState')
    local Assets=module('Data.Assets')
    local States=module('Shared.Types.AreaEggs').States
    local mutations
    pcall(function() mutations=module('Shared.Modules.Mutations') end)

    local latestEntries={}
    local function parseValue(text)
        local amount,suffix=tostring(text):gsub(',',''):match('^%s*%$?%s*(%d+%.?%d*)%s*(%a*)%s*$')
        local powers={['']=1,k=1e3,m=1e6,b=1e9,t=1e12,qa=1e15,qi=1e18}
        local factor=suffix and powers[suffix:lower()]
        if not amount or not factor then return nil end
        local value=tonumber(amount)*factor
        return valid(value) and value or nil
    end

    local lastScan=0
    createFinder({
        gui=gui, player=player, make=make, label=label,
        entries=function() return os.clock()-lastScan<10 and latestEntries or {} end,
        ready=function() return lastScan>0 and os.clock()-lastScan<10 end,
        parseValue=parseValue, money=money, stopFarm=function() end
    })

    while alive do
        pcall(function()
            local snapshot=EggState.ReadFieldEggs()
            local eggs={}
            for recordKey,record in pairs(snapshot.Records) do
                if record.State==States.Slot or record.State==States.Carried then
                    local asset=Assets.Directory[record.AssetCategory] or {}
                    local rarity=asset.Rarity or {}
                    local uid=record.Uid or recordKey
                    local model=modelFor(uid)
                    local scale=numberField(record,{'AssetScale'})
                    local rate=displayedRate(model) or computedRate(asset.EarningRate,scale,record.Mutations or {},mutations)
                    local traits=readTraitNames(record)
                    table.insert(eggs,{
                        uid=uid, category=record.AssetCategory, model=model, icon=asset.Icon,
                        name=asset.DisplayName or record.AssetCategory or 'Unknown',
                        rarity=rarity.DisplayName or 'Unknown', tier=tonumber(rarity.Rank) or 0,
                        scale=scale, rate=rate, mutationText=table.concat(traits,', ')
                    })
                end
            end
            latestEntries=eggs
            lastScan=os.clock()
        end)
        task.wait(2)
    end
end

task.spawn(function()
    pcall(run)
end)
