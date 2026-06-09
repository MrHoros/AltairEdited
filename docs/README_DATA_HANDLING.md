# Data Handling in Altair

This document provides an overview of the data handling system implemented in this Altair-derived branch.

## Overview

The data handling system consists of two main components:

1. **ServerData** - Manages server-side data, including player profiles and game-wide data
2. **ClientData** - Manages client-side data and mirrors server data on the client

The system uses the following libraries:

- **Reflex** for state management
- **ProfileStore** for player profile persistence
- **Signal** for event handling
- **Promise** for asynchronous operations
- **Bridgenet2** for networking (indirectly through remote events)

## Server-Side Data Handling

The `ServerData` module (`src/server/modules/ServerData.luau`) manages server-side data. It has the following responsibilities:

### Server-Side Player Data Management

- Starting a ProfileStore session when a player joins
- Ending the ProfileStore session when a player leaves
- Saving player data through ProfileStore autosave and final `EndSession`
- Providing access to player data through a producer pattern
- Replicating player data changes to the client

### Server-Side Game Data Management

- Managing game-wide data (e.g., server start time, active players)
- Providing access to game data through a producer pattern
- Replicating game data changes to all clients

### Server-Specific Remote Communication

The module sets up the following remote events and functions for communication with clients:

- `ReplicateStore` - For replicating player data changes
- `ReplicateGameStore` - For replicating game data changes
- `GetPlayerData` - For clients to get their player data
- `GetGameData` - For clients to get game data

## Client-Side Data Handling

The `ClientData` module (`src/client/modules/ClientData.luau`) manages client-side data. It has the following responsibilities:

### Client-Side Player Data Management

- Loading player data from the server
- Mirroring server-side player data
- Providing access to player data through a producer pattern
- Replicating player data changes to the server

### Client-Side Game Data Management

- Loading game data from the server
- Mirroring server-side game data
- Providing access to game data through a producer pattern
- Replicating game data changes to the server

### Client-Specific Data Management

- Managing client-specific data (e.g., local settings)
- Providing access to client-specific data through a producer pattern

## Usage Examples

### Server-Side

```luau
-- Get a player's profile
local profile = ServerData:GetPlayerProfile(player)

-- Wait for a player's profile to be loaded
local profileYielded = ServerData:WaitForPlayerProfile(player):expect()

-- Wait for a player's profile.producer to be loaded
ServerData:GetPlayerProducerAsync(player):andThen(function(producer)
    -- Use producer
    local coins = producer:getState().coins
    print("Player has", coins, "coins")

    -- Modify profile data
    producer.addCoins(100)
end)

-- Access game data
local activePlayers = ServerData.gameProducer:getState().activePlayers
print("Active players:", activePlayers)

-- Modify game data
ServerData.gameProducer:setActivePlayers(10)
```

### Client-Side

```luau
-- Get player data
ClientData:GetPlayerProducerAsync():andThen(function(producer)
    -- Use player data
    local coins = producer:getState().coins
    print("I have", coins, "coins")

    -- Modify player data
    producer.addCoins(100)
end)

-- Get game data
ClientData:GetGameProducerAsync():andThen(function(producer)
    -- Use game data
    local activePlayers = producer:getState().activePlayers
    print("Active players:", activePlayers)

    -- Cannot modify game data by client
end)

-- Access client-specific data [WIP]
local musicVolume = ClientData.clientProducer:getState().localSettings.musicVolume
print("Music volume:", musicVolume)

-- Modify client-specific data
ClientData.clientProducer.setLocalSetting("musicVolume", 0.8)
```

## Data Flow

1. When a player joins, the server starts a ProfileStore session
2. The server creates a producer for the player's data
3. The client requests the player's data from the server
4. The client creates a producer for the player's data
5. When the server or client modifies the data, the changes are replicated to the other side
6. When a player leaves, the server writes the producer state into `Profile.Data` and calls `EndSession`

## Security Considerations

- Secure actions (prefixed with "secure") cannot be replicated from the client to the server
- The server validates all data received from clients
- ProfileStore handles session locking, autosave, and session conflict handling
- The server still owns data shape, migration/sanitization, and producer-to-save conversion

## Implementation Details

### Server-Side Implementation

The `ServerData` module is implemented as a controller in the Altair project's module system. It has the following key components:

- `profiles` - A table mapping players to their profiles
- `loadingProfiles` - A table preventing duplicate session starts for the same player
- `gameProducer` - A producer for game-wide data
- `playerDataLoadedEvent` - A signal fired when a player's data is loaded
- `GetPlayerProfile` - A function to get a player's profile
- `WaitForPlayerProfile` - A function to wait for a player's profile to be loaded
- `GetPlayerProducerAsync` - A function to get the player producer asynchronously
- `GetGameProducerAsync` - A function to get the game producer asynchronously
- `PlayerAdded` - A function called when a player joins
- `PlayerRemoving` - A function called when a player leaves
- `Init` - A function called when the module is initialized

The module uses `ProfileStore.New(...)`, `StartSessionAsync(...)`, `OnSessionEnd`, `OnLastSave`, and `EndSession()` instead of the older ProfileService `GetProfileStore(...)`, `LoadProfileAsync(...)`, `ListenToRelease(...)`, and `Release()` API.

### Client-Side Implementation

The `ClientData` module is implemented as a controller in the Altair project's module system. It has the following key components:

- `playerProducer` - A producer for player data
- `gameProducer` - A producer for game data
- `clientProducer` - A producer for client-specific data
- `isPlayerDataLoaded` - A boolean indicating if player data is loaded
- `isGameDataLoaded` - A boolean indicating if game data is loaded
- `playerDataLoadedSignal` - A signal fired when player data is loaded
- `gameDataLoadedSignal` - A signal fired when game data is loaded
- `GetPlayerProducerAsync` - A function to get the player producer asynchronously
- `GetGameProducerAsync` - A function to get the game producer asynchronously
- `PlayerAdded` - A function called when a player joins
- `Init` - A function called when the module is initialized
