local AW_SCREEN_OPEN = false;
local AW_SCREEN_FALSE = false;
local AW_PAGE_NUM = 0;
local AW_QUEUED = false;
local AW_UPDATE_INTERVAL = 0.4;
local AW_LAST_UPDATE = 0;
local AW_CURRENT_SCAN = nil;
local AW_OWNER_QUEUE = {};
local AW_LAST_PAGE = false;
local AW_OWNER_RETRY = false;
AW_SCANS = {};

function AWInitHandler(self)
  self:RegisterEvent("AUCTION_ITEM_LIST_UPDATE");
  self:RegisterEvent("AUCTION_HOUSE_SHOW");
  self:RegisterEvent("AUCTION_HOUSE_CLOSED");
end

-- Trace in pretty colours
function AWTrace(msg)
  if msg ~= nil then
    DEFAULT_CHAT_FRAME:AddMessage('|cFF008AFFA|cFF0095FFu|cFF009FFFc|cFF00AAFFt|cFF00B5FFi|cFF00BFFFo|cFF00CAFFn|cFF00D4FFW|cFF00DFFFh|cFF00EAFFo|cFF00F4FFr|cFF00FFFFe|r: '..msg)
  else
    AWTrace('|cFFFF0000NIL VALUE PASSED TO TRACE!!!');
  end
end

-- ============================================
-- =============Handler functions==============
-- ============================================
function AWEventHandler(self, event, ...)
  if event == "AUCTION_ITEM_LIST_UPDATE" then
    AWItemListHandler();
  elseif event == "AUCTION_HOUSE_SHOW" then
    AWAHDialogHandler(true);
  elseif event == "AUCTION_HOUSE_CLOSED" then
    AWAHDialogHandler(false);
  end
end

-- Slash commands
function AWCommandHandler(msg)
  if msg == 'scan' then
    AWStartScan();
  else
    AWTrace('Unknown Command \''..msg..'\'');
  end
end

-- Called once per frame whenever a page or item query is made
function AWItemListHandler()
  if AW_QUEUED == true and AW_OWNER_RETRY == false then
    local p_batch, p_count = GetNumAuctionItems("list");
    local p_total = ceil(p_count / 50);
    AWTrace('Scanning Auction House Page '..(AW_PAGE_NUM + 1)..'/'..p_total);

    for i = 1, p_batch do
      local name, _, count, _, _, _, 
      minBid, _, buyoutPrice, bidAmount, 
      _, owner, _  = GetAuctionItemInfo("list", i);
      if owner == nil then
        table.insert(AW_OWNER_QUEUE,i)
      else
        AWAddTableItem(name, count, buyoutPrice, bidAmount, minBid, owner);
      end
    end
    if #AW_OWNER_QUEUE > 0 then
    AW_OWNER_RETRY = true;
    AW_COUNT = 0;
    end
    if AW_PAGE_NUM < floor(p_count / 50) then
      AW_PAGE_NUM = AW_PAGE_NUM + 1;
    else
      AW_LAST_PAGE = true;
    end
  end
end

-- This function runs every time a frame is drawn
function AWUpdateHandler(self, elapsed)
  AW_LAST_UPDATE = AW_LAST_UPDATE + elapsed;
  if AW_LAST_UPDATE > AW_UPDATE_INTERVAL then
    if AW_SCREEN_OPEN == false then
      AW_QUEUED = false;
    else
      if AW_QUEUED == true then
        -- try to requery items with missing owners
        if AW_OWNER_RETRY == true then
          AWRetry();
          return;
        end
        -- Start processing the next page
        if AW_LAST_PAGE == false then
          AWQueryPage();
        else
          AW_QUEUED = false;
        end
      end
    end
    AW_LAST_UPDATE = 0;
  end
end

-- When the AH dialog is open, add a button.
function AWAHDialogHandler()
  -- screen is closed, so we are opening it
  if AW_SCREEN_OPEN == false then
    AW_SCREEN_OPEN = true;
    -- create me a button.
    local f = CreateFrame("Button", "", BrowseSearchButton:GetParent(), "OptionsButtonTemplate")
    f:SetWidth(60);
    f:SetText("Scan");
    f:SetPoint("BOTTOMLEFT", 183, 15);
    f:SetScript("OnClick", function (self, button, down)
      AWStartScan();
    end);
    f:Show()
  else
    -- screen is open, so close it.
    -- 2 close events are sent for some strange reason known only to bliz
    if AW_SCREEN_FALSE == false then
	  AW_SCREEN_FALSE = true;
	else
    AW_SCREEN_OPEN = false;
	  AW_SCREEN_FALSE = false;
	end
  end
end

-- ============================================
-- ============GlobalVar functions=============
-- ============================================

-- Create a new scan in the global var
function AWCreateTable(theTime)
  -- Create current scan
  AW_CURRENT_SCAN = tostring(theTime);
  AW_SCANS[AW_CURRENT_SCAN] = {};
end

-- Add an item to the global variable
function AWAddTableItem(name, count, buyoutPrice, bidAmount, minBid, owner)
  table.insert(AW_SCANS[AW_CURRENT_SCAN], {
      itemName=name, 
      itemQuantity=tostring(count), 
      itemBuyout=tostring(buyoutPrice), 
      itemCurrentBid=tostring(bidAmount), 
      itemOriginalBid=tostring(minBid), 
      itemSeller=owner,
      scanTime=AW_CURRENT_SCAN
  });
end

-- Copies a table
function AWCopyTable(t)
  local new = {};
  local i, v = next(t, nil);
  while i do
    new[i] = v;
    i, v = next(t, i);
  end
  return new;
end

-- ============================================
-- ==============Other functions===============
-- ============================================

-- Check the screen is open and init a scan
function AWStartScan()
  if AW_SCREEN_OPEN then
    -- reset variables
    AW_PAGE_NUM = 0;
    AW_LAST_PAGE = false;
    AW_QUEUED = true;
	  -- Create new scan
	  AWCreateTable(time());
  else
    AWTrace('You need to be talking to an auctioneer.')
	  AW_QUEUED = false;
  end
end

-- Queries the current page. Setting off the list event handler.
function AWQueryPage()
  local canQuery, canQueryAll = CanSendAuctionQuery()
  if canQuery == 1 then
    QueryAuctionItems("", 0, 0, 0, 0, 0, AW_PAGE_NUM, 0, 0, 0)
  end
end

-- Tries to determine the owners of items that we don't have owners for.
function AWRetry()
  AW_COUNT = AW_COUNT + 1;
  -- AWTrace(AW_COUNT);
  
  -- Make a temp table to remove found items
  local AW_OWNER_QUEUE_TEMP = AWCopyTable(AW_OWNER_QUEUE);
  -- Loop through
  for i = 1, #AW_OWNER_QUEUE do
    local name, _, count, _, _, _, 
    minBid, _, buyoutPrice, bidAmount, 
    _, owner, _  = GetAuctionItemInfo("list", AW_OWNER_QUEUE[i]);
    if owner ~= nil then
      table.remove(AW_OWNER_QUEUE_TEMP, i);
      AWAddTableItem(name, count, buyoutPrice, bidAmount, minBid, owner);
    end
  end
  -- Reset our list of missing items
  AW_OWNER_QUEUE = AWCopyTable(AW_OWNER_QUEUE_TEMP);
  if #AW_OWNER_QUEUE == 0 then
    AW_OWNER_RETRY = false;
  end
  
  -- 4 seconds have passed with no results for an item. Probably time to give up.
  if AW_OWNER_RETRY == true and AW_COUNT == 10 then
    for i = 1, #AW_OWNER_QUEUE do
      local name, _, count, _, _, _, 
      minBid, _, buyoutPrice, bidAmount, 
      _, _, _  = GetAuctionItemInfo("list", AW_OWNER_QUEUE[i]);
      AWAddTableItem(name, count, buyoutPrice, bidAmount, minBid, '');
    end
    AW_OWNER_QUEUE = {};
    AW_OWNER_RETRY = false;
  end
  -- Reset update interval
  AW_LAST_UPDATE = 0;
end

SLASH_AUCTIONWHORE1 = "/aucwhore"; 
SLASH_AUCTIONWHORE2 = "/aw"; 
SlashCmdList["AUCTIONWHORE"] = AWCommandHandler; 

AWTrace("Loaded")

