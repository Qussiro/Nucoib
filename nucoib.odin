package nucoib

import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:container/queue"
import "core:slice"
import "core:io"
import "core:os"
import "core:mem"
import "base:runtime"
import "base:intrinsics"
import rl "vendor:raylib"

RUNE_COLS              :: 18
RUNE_ROWS              :: 7
RUNE_WIDTH             :: 7
RUNE_HEIGHT            :: 9

TILE_SIZE              :: 8
TILE_ORE_SIZE          :: rl.Vector2{TILE_SIZE, TILE_SIZE}
TILE_CONVEYOR_SIZE     :: rl.Vector2{TILE_SIZE, TILE_SIZE}
TILE_DRILL_SIZE        :: rl.Vector2{2 * TILE_SIZE, 2 * TILE_SIZE}
TILE_MAIN_SIZE         :: rl.Vector2{3 * TILE_SIZE, 3 * TILE_SIZE}
TILE_COAL_STATION_SIZE :: rl.Vector2{2 * TILE_SIZE, 2 * TILE_SIZE}
TILE_SPLITTER_SIZE     :: rl.Vector2{TILE_SIZE, TILE_SIZE}

TILE_ORE               :: rl.Rectangle{144, 0, TILE_ORE_SIZE.x, TILE_ORE_SIZE.y}
TILE_CONVEYOR          :: rl.Rectangle{152, 0, TILE_CONVEYOR_SIZE.x, TILE_CONVEYOR_SIZE.y}
TILE_DRILL             :: rl.Rectangle{160, 0, TILE_DRILL_SIZE.x, TILE_DRILL_SIZE.x}
TILE_MAIN              :: rl.Rectangle{176, 0, TILE_MAIN_SIZE.x, TILE_MAIN_SIZE.y}
TILE_COAL_STATION      :: rl.Rectangle{200, 0, TILE_COAL_STATION_SIZE.x, TILE_COAL_STATION_SIZE.y}
TILE_SPLITTER          :: rl.Rectangle{216, 0, TILE_SPLITTER_SIZE.x, TILE_SPLITTER_SIZE.y}

STOOD_MENU_HEIGHT      :: 4
DIRECTION_MENU_WIDTH   :: 3
DIRECTION_MENU_HEIGHT  :: 3
FPS_MENU_WIDTH         :: 4
FPS_MENU_HEIGHT        :: 3
SLOT_MENU_WIDTH        :: 13
SLOT_MENU_HEIGHT       :: 7

WORLD_WIDTH            :: 1000
WORLD_HEIGHT           :: 1000
WORLD_RECT             :: Rect{{0, 0}, {WORLD_WIDTH, WORLD_HEIGHT}}
SAVE_FILE_NAME         :: "save.bin"

CLUSTER_SIZE           :: 100
CLUSTER_COUNT          :: 10000
MAX_ORE_COUNT          :: 1000
MIN_ORE_COUNT          :: 100

MIN_SCALE              :: f32(1)
MAX_SCALE              :: f32(20)
ORE_SCALE              :: f32(0.5)

MOVE_COOLDOWN          :: f32(0.05)
DIGGING_COOLDOWN       :: f32(0.5)
DRILLING_TIME          :: f32(0.5)
DRILL_SHAKING_SPEED    :: 20
DRILL_MAX_OFFSET       :: 5
DRILL_MAX_ROTATION     :: 5
TRANSPORTATION_SPEED   :: f32(1)
MAX_FUEL               :: 100
DRILL_CAPACITY         :: 100
ENERGY_CAPACITY        :: 100
SELECT_COOLDOWN        :: f32(0.15)
FUEL_TIME              :: f32(4)

LOG_COLOR              :: rl.Color{170, 240, 208, 255}
WARNING_COLOR          :: rl.Color{250, 218, 94, 255}
ERROR_COLOR            :: rl.Color{240, 90, 90, 255}
PANIC_COLOR            :: rl.Color{255, 182, 30, 255}

BG_COLOR               :: rl.Color {0x20, 0x20, 0x20, 0xFF}
DRILL_COLOR            :: rl.Color{247, 143, 168, 255}
SPLITTER_COLOR         :: rl.LIGHTGRAY
COAL_STATION_COLOR     :: rl.GREEN
CONVEYOR_COLOR         :: rl.LIGHTGRAY
BASE_COLOR             :: rl.BEIGE

UI_SCALE               :: 2

Ores      :: [WORLD_WIDTH][WORLD_HEIGHT]Ore
Buildings :: [WORLD_WIDTH][WORLD_HEIGHT]Building
Vec2i     :: [2]int

Player :: struct {
    pos: Vec2i,
}

Building :: union {
    Drill,
    Conveyor,
    Splitter,
    Base,
    Part,
    CoalStation,
}

Rect :: struct {
    pos:  Vec2i,
    size: Vec2i,
}

Drill :: struct {
    ores:             [dynamic]Ore,
    next_tile:        u8,
    drilling_timer:   f32,
    fuel_time:        f32,
    direction:        Direction,
    fuel_slot:        Ore,
    target_offset:    rl.Vector2,
    current_offset:   rl.Vector2,
    target_rotation:  f32,
    current_rotation: f32,
    active:           bool,
}

Conveyor :: struct {
    direction:               Direction,
    ore_type:                OreType,
    transportation_progress: rl.Vector2,
}

Splitter :: struct {
    using conveyor: Conveyor,
    next: Direction,
}

CoalStation :: struct {
    energy:    u8,
    fuel_slot: Ore,
    fuel_time: f32,
    active:    bool,
}

Base :: struct {
    ores: [OreType]int,
}

Part :: struct {
    main_pos: Vec2i,
}

OreType :: enum u8 {
    None,
    Iron,
    Tungsten,
    Coal,
    Copper,
}

Panel :: struct {
    priority:       int,
    rect:           rl.Rectangle,
    pos_percentege: rl.Vector2,
    anchor:         bit_set[Direction],
    active:         bool,
}

PanelType :: enum {
    None,
    Stood,
    Fps,
    Base,
    Direction,
    Use,
}

Ore :: struct {
    type:  OreType,
    count: int,
}

Fill :: enum {
    None,
    All,
    Partial,
}

Direction :: enum u8 {
    Right,
    Down,
    Left,
    Up,
}

ListConf :: struct {
    rect:     rl.Rectangle,
    bg_color: rl.Color,
    fg_color: rl.Color,
    title:    string,
    content:  []ListElement,
}

ListElement :: struct {
    text:    string,
    reverse: bool,
}

State :: struct {
    ores:                 ^Ores,
    buildings:            ^Buildings,
    base:                 ^Base,
    player:               Player,
    font_texture:         rl.Texture2D,
    char_width:           f32,
    char_height:          f32,
    grid_rows:            int,
    grid_cols:            int,
    pressed_move:         f32,
    pressed_dig:          f32,
    selected_ore:         OreType,
    selected_slot:        int,
    selected_drill:       ^Drill,
    count_clusters_sizes: [CLUSTER_SIZE + 1]int,
    temp_buffer:          [512]u8,
    temp_buffer_length:   int,
    window_width:         i32,
    window_height:        i32,
    scale:                f32,
    direction:            Direction,
    blank_texture_rec:    rl.Rectangle,
    panels:               [PanelType]Panel,
    panel_offset:         rl.Vector2,
    current_panel_idx:    PanelType,
    dt:                   f32,
}

s := State {
    window_width  = 1280,
    window_height = 720,
    scale         = 2,
}

offsets := [Direction]Vec2i {
    .Right = {1, 0},
    .Down  = {0, 1},
    .Left  = {-1, 0},
    .Up    = {0, -1},
}

perpendiculars := [Direction]bit_set[Direction] {
    .Right = {.Up, .Down},
    .Down  = {.Left, .Right},
    .Left  = {.Up, .Down},
    .Up    = {.Left, .Right},
}

opposite := [Direction]Direction {
    .Right = .Left,
    .Down  = .Up,
    .Left  = .Right,
    .Up    = .Down,
}

write_save :: proc() -> os.Error {
    _ = os.remove(SAVE_FILE_NAME)
    file := os.open(SAVE_FILE_NAME, os.O_CREATE | os.O_WRONLY, 0o666) or_return
    defer os.close(file)

    os.write(file, mem.ptr_to_bytes(&s.player)) or_return
    os.write(file, mem.ptr_to_bytes(&s.ores[0][0], WORLD_WIDTH * WORLD_HEIGHT)) or_return
    os.write(file, mem.ptr_to_bytes(&s.buildings[0][0], WORLD_WIDTH * WORLD_HEIGHT)) or_return

    for i := 0; i < WORLD_WIDTH; i += 1 {
        for j := 0; j < WORLD_HEIGHT; j += 1 {
            if drill, ok := s.buildings[i][j].(Drill); ok {
                os.write(file, mem.ptr_to_bytes(&Vec2i{i, j})) or_return
                
                ores_length := len(drill.ores)
                os.write(file, mem.ptr_to_bytes(&ores_length)) or_return

                if ores_length != 0 {
                    os.write(file, mem.slice_to_bytes(drill.ores[:])) or_return
                } 
            }
        }
    }
    return nil
}

read_save :: proc() -> os.Error {
    file := os.open(SAVE_FILE_NAME, os.O_RDONLY) or_return
    defer os.close(file)

    os.read(file, mem.ptr_to_bytes(&s.player)) or_return
    os.read(file, mem.ptr_to_bytes(&s.ores[0][0], WORLD_WIDTH * WORLD_HEIGHT)) or_return
    os.read(file, mem.ptr_to_bytes(&s.buildings[0][0], WORLD_WIDTH * WORLD_HEIGHT)) or_return

    for {
        drill_pos: Vec2i
        n, err := os.read(file, mem.ptr_to_bytes(&drill_pos))
        if err == os.ERROR_EOF || n == 0 do break
        if err != nil do return err
       
        drill := &building_ptr_at(drill_pos).(Drill)
        drill.ores = {}
        
        ores_length: int
        _ = os.read(file, mem.ptr_to_bytes(&ores_length)) or_return

        if ores_length != 0 {
            resize(&drill.ores, ores_length)
            _ = os.read(file, mem.slice_to_bytes(drill.ores[:])) or_return
        }
    }

    return nil
}

cluster_generation :: proc(tile: OreType) {
    visited_count := 0
    generated_count := 0
    cx := rand.int_max(WORLD_WIDTH)
    cy := rand.int_max(WORLD_HEIGHT)

    tovisit: queue.Queue(Vec2i)
    visited: [dynamic]Vec2i
    queue.push_back(&tovisit, Vec2i{cx, cy})

    for queue.len(tovisit) > 0 {
        ci := queue.pop_front(&tovisit)
         
        if slice.contains(visited[:], ci) do continue
        append(&visited, ci)
        
        r := rand.float32()
        y := -f32(visited_count) / CLUSTER_SIZE + 1
        visited_count += 1
        if r >= y do continue

        if ci.x - 1 != -1 {
            queue.push_back(&tovisit, Vec2i{ci.x - 1, ci.y})
        }
        if ci.x + 1 != WORLD_WIDTH {
            queue.push_back(&tovisit, Vec2i{ci.x + 1, ci.y})
        }
        if ci.y - 1 != -1 {
            queue.push_back(&tovisit, Vec2i{ci.x, ci.y - 1})
        }
        if ci.y + 1 != WORLD_HEIGHT {
            queue.push_back(&tovisit, Vec2i{ci.x, ci.y + 1})
        }

        count := 0
        if tile != .None {
            min := int(y * MIN_ORE_COUNT)
            max := int(y * MAX_ORE_COUNT)
            count = rand.int_max(max - min) + min
        }

        s.ores[ci.x][ci.y] = {tile, count}
        generated_count += 1
    }

    s.count_clusters_sizes[generated_count] += 1
    delete(visited)
    queue.destroy(&tovisit)
}


recalculate_grid_size :: proc() {
    s.grid_rows = int(f32(s.window_height) / (TILE_SIZE * s.scale))
    s.grid_cols = int(f32(s.window_width) / (TILE_SIZE * s.scale))  
}

try_build :: proc(B: typeid) -> bool {
    ores := get_resources(B)
    for ore in ores {
        if s.base.ores[ore.type] >= ore.count {
            s.base.ores[ore.type] -= ore.count
            continue
        }
        return false
    }
    return true
}

get_resources :: proc(B: typeid) -> []Ore {
    switch B {
        case Drill:
            @(static) ores := []Ore{{.Iron, 5}}
            return ores
        case Conveyor:
            @(static) ores := []Ore{{.Copper, 1}}
            return ores
        case Splitter:
            @(static) ores := []Ore{{.Copper, 1}, {.Iron, 1}}
            return ores
        case CoalStation:
            @(static) ores := []Ore{{.Iron, 5}, {.Copper, 5}}
            return ores
        case:
            nucoib_panic("Couldn't get resources from building: %v", B)
    }
}

input :: proc() {
    if rl.IsWindowResized() {
        s.window_width = rl.GetScreenWidth()
        s.window_height = rl.GetScreenHeight()
        recalculate_grid_size()
        
        for &panel in s.panels {
            panel.rect.x = panel.pos_percentege.x * f32(s.window_width)
            panel.rect.y = panel.pos_percentege.y * f32(s.window_height)
            rect_clamp(&panel.rect, screen_rect())
        }
    }

    if s.pressed_move > 0 {
        s.pressed_move -= s.dt
    } else if s.panels[.Use].active == false {
        if rl.IsKeyDown(.RIGHT) && s.player.pos.x < WORLD_WIDTH - 1 {
            s.player.pos.x += 1
        }
        if rl.IsKeyDown(.DOWN) && s.player.pos.y < WORLD_HEIGHT - 1 {
            s.player.pos.y += 1
        }  
        if rl.IsKeyDown(.LEFT) && s.player.pos.x > 0 {
            s.player.pos.x -= 1 
        }
        if rl.IsKeyDown(.UP) && s.player.pos.y > 0 {
            s.player.pos.y -= 1
        }
        s.pressed_move = MOVE_COOLDOWN
    }

    select: if s.panels[.Use].active {
        if rl.IsKeyPressed(.RIGHT) && s.selected_slot == 0 {
            ore := Ore{s.selected_ore, 0}
            if ore.type != .Coal do break select
            if s.selected_drill.fuel_slot == {} do s.selected_drill.fuel_slot = ore
            if s.selected_drill.fuel_slot.type == ore.type {
                if s.base.ores[ore.type] > 0 && s.selected_drill.fuel_slot.count < MAX_FUEL {
                    if rl.IsKeyDown(.LEFT_SHIFT) {
                        free_space := MAX_FUEL - s.selected_drill.fuel_slot.count
                        s.selected_drill.fuel_slot.count += min(s.base.ores[ore.type], 5, free_space)
                        s.base.ores[ore.type] -= min(s.base.ores[ore.type], 5, free_space)
                    } else {
                        s.selected_drill.fuel_slot.count += 1
                        s.base.ores[ore.type] -= 1
                    }
                }
            } else {
                if s.base.ores[ore.type] > 0 {
                    s.base.ores[s.selected_drill.fuel_slot.type] += s.selected_drill.fuel_slot.count
                    s.selected_drill.fuel_slot = ore
                    s.selected_drill.fuel_slot.count += 1
                    s.base.ores[ore.type] -= 1
                }
            }
        }
        if rl.IsKeyPressed(.LEFT) {
            if s.selected_slot == 0 {
                ore_type := s.selected_drill.fuel_slot.type
                if s.selected_drill.fuel_slot.count > 0 {
                    if rl.IsKeyDown(.LEFT_SHIFT) {
                        s.base.ores[ore_type] += min(s.selected_drill.fuel_slot.count, 5)
                        s.selected_drill.fuel_slot.count -= min(s.selected_drill.fuel_slot.count, 5)
                    } else {
                        s.selected_drill.fuel_slot.count -= 1
                        s.base.ores[ore_type] += 1
                    }
                }
            } else {
                if len(s.selected_drill.ores) > 0 {
                    ore_type := s.selected_drill.ores[0].type
                    if rl.IsKeyDown(.LEFT_SHIFT) {
                        s.base.ores[ore_type] += min(s.selected_drill.ores[0].count, 5)
                        s.selected_drill.ores[0].count -= min(s.selected_drill.ores[0].count, 5)
                    } else {
                        s.selected_drill.ores[0].count -= 1
                        s.base.ores[ore_type] += 1
                    }
                    if s.selected_drill.ores[0].count == 0 do ordered_remove(&s.selected_drill.ores, 0)
                }
            }
        }
        if rl.IsKeyPressed(.DOWN) {
            s.selected_ore = OreType((int(s.selected_ore) + 1) % len(OreType))
        }  
        if rl.IsKeyPressed(.UP) {
            s.selected_ore = OreType(int(s.selected_ore) - 1)
            if s.selected_ore < min(OreType) do s.selected_ore = max(OreType)
        }
        if rl.IsKeyPressed(.TAB) {
            s.selected_slot = (s.selected_slot + 1) % 2
        }  
        s.pressed_move = SELECT_COOLDOWN
    }

    if rl.IsKeyPressed(.MINUS) {
        s.scale = max(MIN_SCALE, s.scale - math.floor(s.scale) * 0.1)
        recalculate_grid_size()
    }
    if rl.IsKeyPressed(.EQUAL) {
        s.scale = min(math.floor(s.scale) * 0.1 + s.scale, MAX_SCALE)
        recalculate_grid_size()
    }

    drill: if rl.IsKeyDown(.D) {
        if check_boundaries(s.player.pos + 1, WORLD_RECT) {
            x := s.player.pos.x
            y := s.player.pos.y
            for i := x; i < x + 2; i += 1 {
                for j := y; j < y + 2; j += 1 {
                     if s.buildings[i][j] != nil do break drill
                }
            }
            if try_build(Drill) {
                s.buildings[x + 1][y + 0] = Part{s.player.pos}
                s.buildings[x + 1][y + 1] = Part{s.player.pos}
                s.buildings[x + 0][y + 1] = Part{s.player.pos}
                s.buildings[x + 0][y + 0] = Drill{direction = s.direction}
            }
        }
    }

    if rl.IsKeyPressed(.R) {
        s.direction = Direction((int(s.direction) + 1) % len(Direction))
    }
    if rl.IsKeyPressed(.GRAVE) {
        s.panels[.Stood].active = !s.panels[.Stood].active
    }
    if rl.IsKeyPressed(.I) {
        s.panels[.Base].active = !s.panels[.Base].active
    }
    if rl.IsKeyPressed(.F1) {
        s.panels[.Fps].active = !s.panels[.Fps].active
    }

    if rl.IsKeyPressed(.E) {
        if s.panels[.Use].active {
            s.panels[.Use].active = false
        } else {
            #partial switch &building in building_ptr_at(s.player.pos)
            {
                case Drill:
                    s.selected_drill = &building
                    s.panels[.Use].active = !s.panels[.Use].active
                case Part:
                    drill, ok := &building_ptr_at(building.main_pos).(Drill)
                    if ok {
                        s.selected_drill = drill
                        s.panels[.Use].active = !s.panels[.Use].active
                    }
                case:
            }
        }
    }

    if rl.IsKeyDown(.C) {
        building := building_ptr_at(s.player.pos)
        conveyor, ok := &building.(Conveyor)

        if (ok && conveyor.direction != s.direction) {
            conveyor.direction = s.direction
        }
        if building^ == nil && try_build(Conveyor) {
            building^ = Conveyor{direction = s.direction}
        }
    }
    
    if rl.IsKeyDown(.V) {
        building := building_ptr_at(s.player.pos)
        splitter, ok := &building.(Splitter)

        if (ok && splitter.direction != s.direction) {
            splitter.direction = s.direction
            splitter.next = s.direction
        }
        if building^ == nil && try_build(Splitter) {
            building^ = Splitter{direction = s.direction, next = s.direction}
        }
    }

    if rl.IsKeyDown(.X) {
        delete_building(s.player.pos)
    }

    if s.pressed_dig > 0 {
        s.pressed_dig -= s.dt
    } else {
        if rl.IsKeyDown(.SPACE) {
            current_tile := &s.ores[s.player.pos.x][s.player.pos.y]
            if current_tile.type != .None {
                s.base.ores[current_tile.type] += 1
                current_tile.count -= 1
                if current_tile.count <= 0 do current_tile.type = .None
                s.pressed_dig = DIGGING_COOLDOWN 
            }
        }
    }

    if rl.IsKeyPressed(.F5) {
        time := rl.GetTime()
        err := write_save()
        if err != nil {
            nucoib_errorfln("Cannot write save file: %v", err)
        } else {
            nucoib_logfln("Saved in %.6vs", rl.GetTime() - time)
        }
    }
    if rl.IsKeyPressed(.F9) {
        time := rl.GetTime()
        err := read_save()
        if err != nil {
            nucoib_errorfln("Cannot read save file: %v", err)
        } else {
            nucoib_logfln("Loaded in %.6vs", rl.GetTime() - time)
        }
    }

    if rl.IsMouseButtonDown(.LEFT) && s.current_panel_idx == .None {
        mouse_pos := rl.GetMousePosition()

        current_panel_index := PanelType.None
        for panel, i in s.panels {
            if check_ui_boundaries(mouse_pos, panel.rect) {
                if (current_panel_index == .None || panel.priority < s.panels[current_panel_index].priority) && panel.active {
                    current_panel_index = i
                }
            }
        }
        s.current_panel_idx = current_panel_index
        if s.current_panel_idx != .None {
            s.panel_offset.x = s.panels[s.current_panel_idx].rect.x - mouse_pos.x
            s.panel_offset.y = s.panels[s.current_panel_idx].rect.y - mouse_pos.y
            prev_priority := s.panels[s.current_panel_idx].priority
            for &panel in s.panels {
                if panel.priority < prev_priority do panel.priority += 1
            }
            s.panels[s.current_panel_idx].priority = 0
        }
    }

    if rl.IsMouseButtonUp(.LEFT) {
        s.current_panel_idx = .None
    }
    
    coal_station: if rl.IsKeyPressed(.K) {
        if check_boundaries(s.player.pos + 1, WORLD_RECT) {
            x := s.player.pos.x
            y := s.player.pos.y
            for i := x; i < x + 2; i += 1 {
                for j := y; j < y + 2; j += 1 {
                     if s.buildings[i][j] != nil do break coal_station
                }
            }
            if try_build(CoalStation) {
                s.buildings[x + 1][y + 0] = Part{s.player.pos}
                s.buildings[x + 1][y + 1] = Part{s.player.pos}
                s.buildings[x + 0][y + 1] = Part{s.player.pos}
                s.buildings[x + 0][y + 0] = CoalStation{}
            }
        }
    }
}

rect_clamp :: proc(inner: ^rl.Rectangle, outer: rl.Rectangle) {
    if inner.x <= outer.x {
        inner.x = outer.x
    }
    if inner.y <= outer.y {
        inner.y = outer.y
    }
    if inner.x + inner.width >= outer.x + outer.width {
        inner.x = outer.x + outer.width - inner.width
    }
    if inner.y + inner.height >= outer.y + outer.height {
        inner.y = outer.y + outer.height - inner.height
    }
}

rect_clamp_sides :: proc(inner: ^rl.Rectangle, outer: rl.Rectangle) -> bit_set[Direction] {
    sides: bit_set[Direction]
    if inner.x <= outer.x {
        inner.x = outer.x
        sides += {.Left}
    }
    if inner.y <= outer.y {
        inner.y = outer.y 
        sides += {.Up}
    }
    if inner.x + inner.width >= outer.x + outer.width {
        inner.x = outer.x + outer.width - inner.width   
        sides += {.Right}
    }
    if inner.y + inner.height >= outer.y + outer.height {
        inner.y = outer.y + outer.height - inner.height 
        sides += {.Down}
    }
    return sides
}

grid_rect :: proc() -> Rect {
    return {{0, 0}, {s.grid_cols, s.grid_rows}}
}

screen_rect :: proc() -> rl.Rectangle {
    return {0, 0, f32(s.window_width), f32(s.window_height)}
}

update :: proc() {
    if s.current_panel_idx != .None {
        panel := &s.panels[s.current_panel_idx]
        panel.rect.x = rl.GetMousePosition().x + s.panel_offset.x
        panel.rect.y = rl.GetMousePosition().y + s.panel_offset.y
        panel.pos_percentege = {
            panel.rect.x / f32(s.window_width),
            panel.rect.y / f32(s.window_height),
        }
        panel.anchor = rect_clamp_sides(&panel.rect, screen_rect())
    }

    for &panel in s.panels {
        switch panel.anchor {
            case {.Left}:
                panel.rect.x = 0
            case {.Up}:
                panel.rect.y = 0
            case {.Right}:
                panel.rect.x = f32(s.window_width)- panel.rect.width
            case {.Down}:
                panel.rect.y = f32(s.window_height)- panel.rect.height
            case {.Left, .Up}:
                panel.rect.x = 0
                panel.rect.y = 0
            case {.Left, .Down}:
                panel.rect.x = 0
                panel.rect.y = f32(s.window_height)- panel.rect.height
            case {.Right, .Up}:
                panel.rect.x = f32(s.window_width)- panel.rect.width
                panel.rect.y = 0
            case {.Right, .Down}:
                panel.rect.x = f32(s.window_width)- panel.rect.width
                panel.rect.y = f32(s.window_height)- panel.rect.height
            case {.Left, .Right}:
                panel.rect.x = f32(s.window_width)/2 - panel.rect.width/2
            case {.Up, .Down}:
                panel.rect.y = f32(s.window_height)/2 - panel.rect.height/2
            case {.Left, .Up, .Right, .Down}:
                panel.rect.x = f32(s.window_width)/2 - panel.rect.width/2
                panel.rect.y = f32(s.window_height)/2 - panel.rect.height/2
            case {}:
            case:
                nucoib_warningfln("Strange direction combination: %v", panel.anchor)
                panel.anchor = {}
        }
    }

    for i := 0; i < WORLD_WIDTH; i += 1 {
        for j := 0; j < WORLD_HEIGHT; j += 1 {
            switch &building in s.buildings[i][j] {
                case nil:
                case Drill:
                    building.active = false
                    if building.fuel_time < 0 && building.fuel_slot.count > 0 {
                        building.fuel_time = FUEL_TIME
                        building.fuel_slot.count -= 1
                        if building.fuel_slot.count == 0 do building.fuel_slot = {}
                    }
                    if building.fuel_time >= 0 {
                        next_ore := &s.ores[i + int(building.next_tile) % 2][j + int(building.next_tile) / 2]
                        if building.drilling_timer >= DRILLING_TIME {
                            if drill_ore_count(building) < DRILL_CAPACITY {
                                if next_ore.type != .None {
                                    ores := building.ores[:]
                                    if !slice.is_empty(ores) && slice.last(ores).type == next_ore.type {
                                        slice.last_ptr(ores).count += 1
                                    } else {
                                        append(&building.ores, Ore{next_ore.type, 1})
                                    }

                                    next_ore.count -= 1
                                    if next_ore.count <= 0 do next_ore^ = {}
                                }
                                building.next_tile = (building.next_tile + 1) % 4
                            }
                            building.drilling_timer = 0
                        }
                        if drill_ore_count(building) < DRILL_CAPACITY {
                            building.fuel_time -= s.dt
                            building.active = true
                        }
                        building.drilling_timer += s.dt

                        dump_area := [2]Vec2i{{i, j}, {i, j}}
                        switch building.direction {
                            case .Right:
                                dump_area[0] += 2 * offsets[building.direction]
                                dump_area[1] += 2 * offsets[building.direction] + {0, 1}
                            case .Down:
                                dump_area[0] += 2 * offsets[building.direction]
                                dump_area[1] += 2 * offsets[building.direction] + {1, 0}
                            case .Left:
                                dump_area[0] += offsets[building.direction]
                                dump_area[1] += offsets[building.direction] + {0, 1}
                            case .Up:
                                dump_area[0] += offsets[building.direction]
                                dump_area[1] += offsets[building.direction] + {1, 0}
                        }
                        for pos in dump_area {
                            if check_boundaries(pos, WORLD_RECT) {
                                #partial switch &b in building_ptr_at(pos) {
                                    case Conveyor:
                                        if b.ore_type == .None && drill_ore_count(building) > 0 {
                                            b.transportation_progress = 0.5
                                            b.ore_type = building.ores[0].type
                                            building.ores[0].count -= 1
                                            if building.ores[0].count <= 0 do ordered_remove(&building.ores, 0)
                                        }
                                    case Splitter:
                                        if b.ore_type == .None && drill_ore_count(building) > 0 {
                                            b.transportation_progress = 0.5
                                            b.ore_type = building.ores[0].type
                                            building.ores[0].count -= 1
                                            if building.ores[0].count <= 0 do ordered_remove(&building.ores, 0)
                                        }
                                }
                            }
                        }
                    }
                case Conveyor:
                    if building.ore_type == .None do continue
                    switch building.direction {
                        case .Right:
                            building.transportation_progress.x += s.dt * TRANSPORTATION_SPEED
                            if abs(0.5 - building.transportation_progress.y) < 0.01 {
                                building.transportation_progress.y = 0.5
                            } else {
                                building.transportation_progress.y += s.dt * TRANSPORTATION_SPEED * math.sign(0.5 - building.transportation_progress.y)
                            }
                        case .Down:
                            building.transportation_progress.y += s.dt * TRANSPORTATION_SPEED
                            if abs(0.5 - building.transportation_progress.x) < 0.01 {
                                building.transportation_progress.x = 0.5
                            } else {
                                building.transportation_progress.x += s.dt * TRANSPORTATION_SPEED * math.sign(0.5 - building.transportation_progress.x)
                            }
                        case .Left:
                            building.transportation_progress.x -= s.dt * TRANSPORTATION_SPEED
                            if abs(0.5 - building.transportation_progress.y) < 0.01 {
                                building.transportation_progress.y = 0.5
                            } else {
                                building.transportation_progress.y += s.dt * TRANSPORTATION_SPEED * math.sign(0.5 - building.transportation_progress.y)
                            }
                        case .Up:
                            building.transportation_progress.y -= s.dt * TRANSPORTATION_SPEED
                            if abs(0.5 - building.transportation_progress.x) < 0.01 {
                                building.transportation_progress.x = 0.5
                            } else {
                                building.transportation_progress.x += s.dt * TRANSPORTATION_SPEED * math.sign(0.5 - building.transportation_progress.x)
                            }
                    }
                    next_pos := offsets[building.direction] + {i, j}
                    transport_ore(next_pos, &building)
                    building.transportation_progress = rl.Vector2Clamp(building.transportation_progress, 0, 1)
                case Splitter:
                    if building.ore_type == .None do continue

                    can_transfer := true
                    check: if building_at(offsets[building.next] + {i, j}) == nil {
                        for direction in Direction {
                            if direction == opposite[building.direction] do continue

                            if building_at(offsets[direction] + {i, j}) != nil {
                                building.next = direction
                                break check
                            }
                        } 
                        can_transfer = false
                    }

                    if can_transfer {
                        switch building.next {
                            case .Right:
                                building.transportation_progress.x += s.dt * TRANSPORTATION_SPEED
                                if abs(0.5 - building.transportation_progress.y) < 0.01 {
                                    building.transportation_progress.y = 0.5
                                } else {
                                    building.transportation_progress.y += s.dt * TRANSPORTATION_SPEED * math.sign(0.5 - building.transportation_progress.y)
                                }
                            case .Down:
                                building.transportation_progress.y += s.dt * TRANSPORTATION_SPEED
                                if abs(0.5 - building.transportation_progress.x) < 0.01 {
                                    building.transportation_progress.x = 0.5
                                } else {
                                    building.transportation_progress.x += s.dt * TRANSPORTATION_SPEED * math.sign(0.5 - building.transportation_progress.x)
                                }
                            case .Left:
                                building.transportation_progress.x -= s.dt * TRANSPORTATION_SPEED
                                if abs(0.5 - building.transportation_progress.y) < 0.01 {
                                    building.transportation_progress.y = 0.5
                                } else {
                                    building.transportation_progress.y += s.dt * TRANSPORTATION_SPEED * math.sign(0.5 - building.transportation_progress.y)
                                }
                            case .Up:
                                building.transportation_progress.y -= s.dt * TRANSPORTATION_SPEED
                                if abs(0.5 - building.transportation_progress.x) < 0.01 {
                                    building.transportation_progress.x = 0.5
                                } else {
                                    building.transportation_progress.x += s.dt * TRANSPORTATION_SPEED * math.sign(0.5 - building.transportation_progress.x)
                                }
                        }
                        next_pos := offsets[building.next] + {i, j}
                    
                        // Kinda BRUH
                        direction := building.direction
                        building.direction = building.next
                        transport_ore(next_pos, &building)
                        building.direction = direction
                    
                        if building.transportation_progress == 0 {
                            building.next = Direction((int(building.next) + 1) % len(Direction))
                            for building_at(offsets[building.next] + {i, j}) == nil || building.next == opposite[building.direction] {
                                building.next = Direction((int(building.next) + 1) % len(Direction))
                            } 
                        }
                        building.transportation_progress = rl.Vector2Clamp(building.transportation_progress, 0, 1)
                    } else {
                        switch building.next {
                            case .Right:
                                if building.transportation_progress.x < 0.5 {
                                    building.transportation_progress.x += s.dt * TRANSPORTATION_SPEED
                                }
                                if abs(0.5 - building.transportation_progress.y) < 0.01 {
                                    building.transportation_progress.y = 0.5
                                } else {
                                    building.transportation_progress.y += s.dt * TRANSPORTATION_SPEED * math.sign(0.5 - building.transportation_progress.y)
                                }
                            case .Down:
                                if building.transportation_progress.y < 0.5 {
                                    building.transportation_progress.y += s.dt * TRANSPORTATION_SPEED
                                }
                                if abs(0.5 - building.transportation_progress.x) < 0.01 {
                                    building.transportation_progress.x = 0.5
                                } else {
                                    building.transportation_progress.x += s.dt * TRANSPORTATION_SPEED * math.sign(0.5 - building.transportation_progress.x)
                                }
                            case .Left:
                                if building.transportation_progress.x > 0.5 {
                                    building.transportation_progress.x -= s.dt * TRANSPORTATION_SPEED
                                }
                                if abs(0.5 - building.transportation_progress.y) < 0.01 {
                                    building.transportation_progress.y = 0.5
                                } else {
                                    building.transportation_progress.y += s.dt * TRANSPORTATION_SPEED * math.sign(0.5 - building.transportation_progress.y)
                                }
                            case .Up:
                                if building.transportation_progress.y > 0.5 {
                                    building.transportation_progress.y -= s.dt * TRANSPORTATION_SPEED
                                }
                                if abs(0.5 - building.transportation_progress.x) < 0.01 {
                                    building.transportation_progress.x = 0.5
                                } else {
                                    building.transportation_progress.x += s.dt * TRANSPORTATION_SPEED * math.sign(0.5 - building.transportation_progress.x)
                                }
                        }
                    }
                    
                case CoalStation:
                    building.energy = 0
                    building.active = false
                    if building.fuel_time < 0 && building.fuel_slot.count > 0 {
                        building.fuel_time = FUEL_TIME
                        building.fuel_slot.count -= 1
                        if building.fuel_slot.count == 0 do building.fuel_slot = {}
                    }
                    if building.fuel_time >= 0 {
                        building.active = true
                        building.energy = 100
                        building.fuel_time -= s.dt
                    }
                case Base:
                case Part:
            }
        }
    }
}

check_conveyor_progress :: proc(conveyor: Conveyor) -> bool {
    switch conveyor.direction {
        case .Right:
            return conveyor.transportation_progress.x >= 1
        case .Left:
            return conveyor.transportation_progress.x <= 0
        case .Down:
            return conveyor.transportation_progress.y >= 1
        case .Up:
            return conveyor.transportation_progress.y <= 0
    }
    nucoib_panic("Strange conveyor direction: %v", conveyor.direction)
}

transport_ore :: proc(next_pos: Vec2i, conveyor: ^Conveyor) {
    if check_boundaries(next_pos, WORLD_RECT) {
        switch &nb in building_ptr_at(next_pos) {
            case Drill:
                if check_conveyor_progress(conveyor^) && conveyor.ore_type == .Coal && nb.fuel_slot.count < MAX_FUEL {
                    if nb.fuel_slot == {} {
                        nb.fuel_slot = {.Coal, 1}
                    } else {
                        nb.fuel_slot.count += 1
                    }
                    conveyor.ore_type = .None
                    conveyor.transportation_progress = 0
                }
            case Conveyor:
                if nb.ore_type == .None && nb.direction != opposite[conveyor.direction] {
                    if check_conveyor_progress(conveyor^) {
                        switch conveyor.direction {
                            case .Right:
                                nb.transportation_progress = {0, conveyor.transportation_progress.y}
                            case .Down:
                                nb.transportation_progress = {conveyor.transportation_progress.x, 0}
                            case .Left:
                                nb.transportation_progress = {1, conveyor.transportation_progress.y}
                            case .Up:
                                nb.transportation_progress = {conveyor.transportation_progress.x, 1}
                        }
                        nb.ore_type = conveyor.ore_type
                        conveyor.ore_type = .None
                        conveyor.transportation_progress = 0
                    }
                }
            case Splitter:
                if nb.ore_type == .None && nb.direction != opposite[conveyor.direction] {
                    if check_conveyor_progress(conveyor^) {
                        switch conveyor.direction {
                            case .Right:
                                nb.transportation_progress = {0, conveyor.transportation_progress.y}
                            case .Down:
                                nb.transportation_progress = {conveyor.transportation_progress.x, 0}
                            case .Left:
                                nb.transportation_progress = {1, conveyor.transportation_progress.y}
                            case .Up:
                                nb.transportation_progress = {conveyor.transportation_progress.x, 1}
                        }
                        nb.ore_type = conveyor.ore_type
                        conveyor.ore_type = .None
                        conveyor.transportation_progress = 0
                    }
                }
            case Base:
                if check_conveyor_progress(conveyor^) {
                    nb.ores[conveyor.ore_type] += 1
                    conveyor.ore_type = .None
                    conveyor.transportation_progress = 0
                }
            case Part:
                transport_ore(nb.main_pos, conveyor)
            case CoalStation:
                if check_conveyor_progress(conveyor^) && conveyor.ore_type == .Coal && nb.fuel_slot.count < MAX_FUEL {
                    if nb.fuel_slot == {} {
                        nb.fuel_slot = {.Coal, 1}
                    } else {
                        nb.fuel_slot.count += 1
                    }
                    conveyor.ore_type = .None
                    conveyor.transportation_progress = 0
                }
        }
    }
}

building_at :: proc(pos: Vec2i) -> Building {
    return s.buildings[pos.x][pos.y]
}

building_ptr_at :: proc(pos: Vec2i) -> ^Building {
    return &s.buildings[pos.x][pos.y]
}

check_boundaries :: proc(pos: Vec2i, rect: Rect) -> bool {
    return pos.x >= rect.pos.x && pos.x < rect.pos.x + rect.size.y && pos.y >= rect.pos.y && pos.y < rect.pos.y + rect.size.y
}

check_ui_boundaries :: proc(pos: rl.Vector2, rect: rl.Rectangle) -> bool {
    return pos.x >= rect.x && pos.x < rect.x + rect.width && pos.y >= rect.y && pos.y < rect.y + rect.height
}

drill_ore_count :: proc(drill: Drill) -> int {
    count: int = 0
    for ore in drill.ores {
        count += ore.count
    }
    return count
}

world_to_screen :: proc(world_pos: Vec2i) -> rl.Vector2 {
    return rl.Vector2 {
        f32(world_pos.x - s.player.pos.x + s.grid_cols/2) * TILE_SIZE * s.scale,
        f32(world_pos.y - s.player.pos.y + s.grid_rows/2) * TILE_SIZE * s.scale,
    }
}

grid_to_screen :: proc(grid_pos: Vec2i) -> rl.Vector2 {
    return rl.Vector2 {
        f32(grid_pos.x) * TILE_SIZE * s.scale,
        f32(grid_pos.y) * TILE_SIZE * s.scale,
    }
}

screen_to_grid :: proc(screen_pos: rl.Vector2) -> Vec2i {
    return Vec2i {
        int(screen_pos.x / TILE_SIZE / s.scale),
        int(screen_pos.y / TILE_SIZE / s.scale),
    }
}

building_to_string :: proc(building: Building) -> string {
    switch b in building {
        case Drill:    
            if len(b.ores) == 0 {
                return tbprintf("Drill[:]")
            } else {
                return tbprintf("Drill[%v:%v]", b.ores[0].type, b.ores[0].count)
            }
        case nil:         return tbprintf("None")
        case Conveyor:    return tbprintf("Conveyor_%v[%v]", b.direction, b.ore_type)
        case Splitter:    return tbprintf("Splitter_%v[%v]", b.direction, b.ore_type)
        case Base:        return tbprintf("Base")
        case Part:        return building_to_string(building_at(b.main_pos))  
        case CoalStation: return tbprintf("CoalStation[%v:%v]", b.energy, b.fuel_slot.count)
        case:          nucoib_panic("Unknown building type %v", b)
    }
}

delete_building :: proc(pos: Vec2i) {
    switch building in building_ptr_at(pos) {
        case nil:
        case Drill:
            building_ptr_at(pos + {0, 0})^ = nil
            building_ptr_at(pos + {1, 0})^ = nil
            building_ptr_at(pos + {1, 1})^ = nil
            building_ptr_at(pos + {0, 1})^ = nil
            for ore in get_resources(Drill) {
                s.base.ores[ore.type] += ore.count 
            }
        case Conveyor:
            building_ptr_at(pos)^ = nil
            for ore in get_resources(Conveyor) {
                s.base.ores[ore.type] += ore.count 
            }
        case Splitter:
            building_ptr_at(pos)^ = nil
            for ore in get_resources(Splitter) {
                s.base.ores[ore.type] += ore.count 
            }
        case Base:
            // You cannot delete the Base
        case Part:
            delete_building(building.main_pos)
        case CoalStation:
            building_ptr_at(pos + {0, 0})^ = nil
            building_ptr_at(pos + {1, 0})^ = nil
            building_ptr_at(pos + {1, 1})^ = nil
            building_ptr_at(pos + {0, 1})^ = nil
            for ore in get_resources(CoalStation) {
                s.base.ores[ore.type] += ore.count 
            }
    }
}

new_rect :: proc(pos: rl.Vector2, size: rl.Vector2) -> rl.Rectangle {
    return {pos.x + 0.5 * size.x * s.scale, pos.y + 0.5 * size.y * s.scale, size.x * s.scale, size.y * s.scale}
}

draw_building :: proc(world_pos: Vec2i, reverse: bool = false) {
    pos := world_to_screen(world_pos)
    switch &building in building_ptr_at(world_pos) {
        case nil: 
        case Drill:
            // TODO: cringe code make better MAYBE 
            if building.active {
                if rl.Vector2Length(building.target_offset - building.current_offset) > DRILL_SHAKING_SPEED*0.05 {
                    building.current_offset += (building.target_offset - building.current_offset)/rl.Vector2Length(building.target_offset - building.current_offset) * DRILL_SHAKING_SPEED * s.dt
                } else {
                    building.target_offset = {rand.float32() * DRILL_MAX_OFFSET - DRILL_MAX_OFFSET, rand.float32() * DRILL_MAX_OFFSET - DRILL_MAX_OFFSET}
                }
                if abs(building.target_rotation - building.current_rotation) > DRILL_SHAKING_SPEED*0.05 {
                    building.current_rotation += (building.target_rotation - building.current_rotation)/abs(building.target_rotation - building.current_rotation) * DRILL_SHAKING_SPEED * s.dt
                } else {
                    building.target_rotation = rand.float32() * DRILL_MAX_ROTATION - DRILL_MAX_ROTATION
                }                
            } else {
                building.current_offset = 0
                building.current_rotation = 0
            }
            dest := new_rect(pos+building.current_offset, TILE_DRILL_SIZE)
            
            
            switch building.direction {
                case .Right: draw_sprite_pro(TILE_DRILL, dest, BG_COLOR, DRILL_COLOR, reverse, 0+building.current_rotation)
                case .Down:  draw_sprite_pro(TILE_DRILL, dest, BG_COLOR, DRILL_COLOR, reverse, 90+building.current_rotation)
                case .Left:  draw_sprite_pro(TILE_DRILL, dest, BG_COLOR, DRILL_COLOR, reverse, 180+building.current_rotation)
                case .Up:    draw_sprite_pro(TILE_DRILL, dest, BG_COLOR, DRILL_COLOR, reverse, 270+building.current_rotation)
            }
            
        case Conveyor:
            dest := new_rect(pos, TILE_ORE_SIZE)
            switch building.direction {
                case .Right: draw_sprite_pro(TILE_CONVEYOR, dest, rl.GRAY, CONVEYOR_COLOR, reverse, 0)
                case .Down:  draw_sprite_pro(TILE_CONVEYOR, dest, rl.GRAY, CONVEYOR_COLOR, reverse, 90)
                case .Left:  draw_sprite_pro(TILE_CONVEYOR, dest, rl.GRAY, CONVEYOR_COLOR, reverse, 180)
                case .Up:    draw_sprite_pro(TILE_CONVEYOR, dest, rl.GRAY, CONVEYOR_COLOR, reverse, 270)
            }
        case Splitter:
            dest := new_rect(pos, TILE_ORE_SIZE)
            switch building.direction {
                case .Right: draw_sprite_pro(TILE_SPLITTER, dest, rl.GRAY, SPLITTER_COLOR, reverse, 0)
                case .Down:  draw_sprite_pro(TILE_SPLITTER, dest, rl.GRAY, SPLITTER_COLOR, reverse, 90)
                case .Left:  draw_sprite_pro(TILE_SPLITTER, dest, rl.GRAY, SPLITTER_COLOR, reverse, 180)
                case .Up:    draw_sprite_pro(TILE_SPLITTER, dest, rl.GRAY, SPLITTER_COLOR, reverse, 270)
            }
        case Base:
            dest := new_rect(pos, TILE_MAIN_SIZE)
            draw_sprite_pro(TILE_MAIN, dest, BG_COLOR, BASE_COLOR, reverse, 0)
        case CoalStation:
            dest: rl.Rectangle
            if building.active {
                squash := f32(math.sin(rl.GetTime()*3) + 1)/8 + 0.75
            
                dest = rl.Rectangle {
                    x = pos.x + 0.5 * TILE_COAL_STATION_SIZE.x * s.scale,
                    y = pos.y + (0.5 + (1 - squash)/2) * TILE_COAL_STATION_SIZE.y * s.scale,
                    width = TILE_COAL_STATION_SIZE.x * s.scale * (1-squash + 0.75),
                    height = TILE_COAL_STATION_SIZE.y * s.scale * squash,
                }
            } else {
                dest = rl.Rectangle {
                    x = pos.x + 0.5 * TILE_COAL_STATION_SIZE.x * s.scale,
                    y = pos.y + 0.5 * TILE_COAL_STATION_SIZE.y * s.scale,
                    width = TILE_COAL_STATION_SIZE.x * s.scale,
                    height = TILE_COAL_STATION_SIZE.y * s.scale,
                }
            }
            
            draw_sprite_pro(TILE_COAL_STATION, dest, BG_COLOR, COAL_STATION_COLOR, reverse, 0)
        case Part:
            if reverse {
                draw_building(building.main_pos, reverse)
            }
    }
}

draw :: proc() {
    rl.ClearBackground(BG_COLOR)

    first_col := max(0, s.player.pos.x - s.grid_cols/2)
    last_col  := min(s.player.pos.x + (s.grid_cols + 1)/2 + 1, WORLD_WIDTH)
    first_row := max(0, s.player.pos.y - s.grid_rows/2)
    last_row  := min(s.player.pos.y + (s.grid_rows + 1)/2 + 1, WORLD_HEIGHT)
    
    // Draw ores
    for i := first_col; i < last_col; i += 1 {
        for j := first_row; j < last_row; j += 1 {
            if s.buildings[i][j] != nil do continue

            ore_color := get_ore_color(s.ores[i][j].type)
            pos := world_to_screen({i, j})
            under_player := s.player.pos == {i, j}
            dest := new_rect(pos, TILE_ORE_SIZE)
            draw_sprite_pro(TILE_ORE, dest, BG_COLOR, ore_color, under_player, 0)
        }
    }

    // Draw buildings
    for i := first_col; i < last_col; i += 1 {
        for j := first_row; j < last_row; j += 1 {
            under_player := s.player.pos == {i, j}
            draw_building({i, j}, under_player)
        }
    }

    // Draw on conveyor
    for i := first_col; i < last_col; i += 1 {
        for j := first_row; j < last_row; j += 1 {
            building: ^Conveyor
            #partial switch &b in s.buildings[i][j] {
                case Conveyor:
                    building = &b
                case Splitter:
                    building = &b
            }
            if building != nil && building.ore_type != .None {
                pos := world_to_screen({i, j})
                
                // No more magic stuff, wide peepo sadge
                ore_offset := building.transportation_progress * s.scale * TILE_SIZE
                ore_offset += pos
                ore_color := get_ore_color(building.ore_type)
                dest := new_rect(ore_offset - 0.5 * TILE_ORE_SIZE * ORE_SCALE * s.scale, TILE_ORE_SIZE * ORE_SCALE)
                draw_sprite_pro(TILE_ORE, dest, rl.BLANK, ore_color, false, 0)
            }
        }
    }

    // Player
    if s.ores[s.player.pos.x][s.player.pos.y].type == .None && building_at(s.player.pos) == nil {
        dest := new_rect(world_to_screen(s.player.pos), TILE_SIZE)
        draw_sprite_pro(TILE_ORE, dest, rl.WHITE, rl.WHITE, false, 0)
    } 
    
    // TODO: nuke this shit
    if _, station_ok := building_at(s.player.pos).(CoalStation); station_ok  {
        rl.DrawCircleLinesV(world_to_screen(s.player.pos+1), 20 * s.scale * TILE_SIZE, rl.YELLOW)
    } 
    if part, part_ok := building_at(s.player.pos).(Part); part_ok {
        if _, station_ok := building_at(part.main_pos).(CoalStation); station_ok {
            rl.DrawCircleLinesV(world_to_screen(part.main_pos+1), 20 * s.scale * TILE_SIZE, rl.YELLOW)
        } 
    }

    clear_temp_buffer()

    panels_indexes: [len(PanelType)]PanelType
    for _, i in s.panels {
        panels_indexes[i] = i
    }

    for i := 0; i < len(panels_indexes); i += 1 {
        for j := 0; j < len(panels_indexes) - i - 1; j += 1 {
            if s.panels[panels_indexes[j]].priority < s.panels[panels_indexes[j + 1]].priority {
                panels_indexes[j], panels_indexes[j + 1] = panels_indexes[j + 1], panels_indexes[j]
            }
        }
    }

    for panel_idx in panels_indexes {
        panel := &s.panels[panel_idx]
        #partial switch panel_idx {
            case .None:
            case .Base:
                elements: [len(OreType)]ListElement 
                for ore_tile in OreType {
                    elements[ore_tile] = {tbprintf("%v: %v", ore_tile, s.base.ores[ore_tile]), false}
                }

                str_length: int
                for element in elements {
                    if len(element.text) > str_length do str_length = len(element.text)
                }

                panel.rect.width = f32(str_length + 2) * RUNE_WIDTH * UI_SCALE 
                panel.rect.height = (len(OreType) + 2) * RUNE_HEIGHT * UI_SCALE

                if panel.active {
                    conf := ListConf{
                        panel.rect,
                        BG_COLOR,
                        rl.WHITE,
                        "MAIN",
                        elements[:],
                    }
                    draw_list(conf)
                }
            case .Direction:
                panel.rect.width = DIRECTION_MENU_WIDTH * RUNE_WIDTH * UI_SCALE
                panel.rect.height = DIRECTION_MENU_HEIGHT * RUNE_HEIGHT * UI_SCALE
                draw_border(panel.rect, BG_COLOR)

                pos := rl.Vector2{panel.rect.x + RUNE_WIDTH * UI_SCALE, panel.rect.y + RUNE_HEIGHT * UI_SCALE}
                switch s.direction {
                    case .Right: draw_char('>' + 0, pos, fg_color = rl.SKYBLUE)
                    case .Down:  draw_char('~' + 1, pos, fg_color = rl.SKYBLUE)
                    case .Left:  draw_char('<' + 0, pos, fg_color = rl.SKYBLUE)
                    case .Up:    draw_char('~' + 2, pos, fg_color = rl.SKYBLUE)
                }
            case .Stood:
                elements: [2]ListElement
                elements[0] = {building_to_string(building_at(s.player.pos)), false}
                title := "STOOD-ON"

                ore := &s.ores[s.player.pos.x][s.player.pos.y]
                #partial switch ore.type {
                    case .None:
                        elements[1] = {tbprintf("None"), false}
                    case: 
                        elements[1] = {tbprintf("%v: %v", ore.type, ore.count), false}
                }
                panel.rect.width = f32(max(len(elements[0].text), len(elements[1].text), len(title) + 2) + 2) * RUNE_WIDTH * UI_SCALE
                panel.rect.height = STOOD_MENU_HEIGHT * RUNE_HEIGHT * UI_SCALE

                if panel.active {
                    // Ore text
                    conf := ListConf {
                        panel.rect,
                        BG_COLOR,
                        rl.WHITE,
                        title,
                        elements[:],
                    }
                    draw_list(conf)
                }
            case .Use:
                elements: [len(OreType)]ListElement
                panel.rect.width = s.panels[.Base].rect.width + (SLOT_MENU_WIDTH - 1) * RUNE_WIDTH * UI_SCALE 
                panel.rect.height = s.panels[.Base].rect.height

                // Use menu
                for ore_tile in OreType {
                    if OreType(s.selected_ore) == ore_tile {
                        elements[ore_tile] = {tbprintf("%v: %v", ore_tile, s.base.ores[ore_tile]), true}
                    } else {
                        elements[ore_tile] = {tbprintf("%v: %v", ore_tile, s.base.ores[ore_tile]), false}
                    }
                }

                if panel.active {
                    right_menu_rect := rl.Rectangle{
                        panel.rect.x + s.panels[.Base].rect.width - RUNE_WIDTH * UI_SCALE,
                        panel.rect.y,
                        SLOT_MENU_WIDTH * RUNE_WIDTH * UI_SCALE, 
                        SLOT_MENU_HEIGHT * RUNE_HEIGHT * UI_SCALE,
                    }
                    draw_border(right_menu_rect, BG_COLOR, title = "USE")

                    slot_rect := rl.Rectangle{
                        right_menu_rect.x + (SLOT_MENU_WIDTH/4 - 1) * RUNE_WIDTH * UI_SCALE,
                        right_menu_rect.y + (SLOT_MENU_HEIGHT/2 - 1) * RUNE_HEIGHT * UI_SCALE,
                        3 * RUNE_WIDTH * UI_SCALE,
                        3 * RUNE_HEIGHT * UI_SCALE,
                    }
                    draw_border(slot_rect, BG_COLOR)
                    c := get_char(s.selected_drill.fuel_slot.type)
                    draw_char(c, {slot_rect.x + RUNE_WIDTH * UI_SCALE, slot_rect.y + RUNE_HEIGHT * UI_SCALE}, reverse = s.selected_slot == 0)

                    bar_pos := rl.Vector2{slot_rect.x + 3 * RUNE_WIDTH * UI_SCALE, slot_rect.y}
                    source := rl.Rectangle {
                        x = f32(int('|' - 32) % RUNE_COLS) * RUNE_WIDTH,
                        y = f32(int('|' - 32) / RUNE_COLS) * RUNE_HEIGHT,
                        width = RUNE_WIDTH,
                        height = RUNE_HEIGHT,
                    }

                    dest := rl.Rectangle {
                        x = bar_pos.x,
                        y = bar_pos.y,
                        width = RUNE_WIDTH * UI_SCALE,
                        height = RUNE_HEIGHT * UI_SCALE * s.selected_drill.fuel_time / FUEL_TIME * 3,
                    }

                    rl.DrawTexturePro(s.font_texture, source, dest, {}, 0, rl.WHITE)
                    slot_text_pos := rl.Vector2{slot_rect.x, slot_rect.y + 3 * RUNE_HEIGHT * UI_SCALE}
                    draw_text(tbprintf("%3.v", s.selected_drill.fuel_slot.count), slot_text_pos)

                    slot_rect = rl.Rectangle{
                        right_menu_rect.x + (SLOT_MENU_WIDTH/2 + SLOT_MENU_WIDTH/4 - 1) * RUNE_WIDTH * UI_SCALE,
                        right_menu_rect.y + (SLOT_MENU_HEIGHT/2 - 1) * RUNE_HEIGHT * UI_SCALE,
                        3 * RUNE_WIDTH * UI_SCALE,
                        3 * RUNE_HEIGHT * UI_SCALE,
                    }
                    slot_text_pos = rl.Vector2{slot_rect.x, slot_rect.y + 3 * RUNE_HEIGHT * UI_SCALE}
                    
                    draw_border(slot_rect, BG_COLOR)
                    if len(s.selected_drill.ores) == 0 {
                        c = get_char(.None)
                        draw_text(tbprintf("000"), slot_text_pos)
                    } else {
                        c = get_char(s.selected_drill.ores[0].type)
                        draw_text(tbprintf("%3.v", s.selected_drill.ores[0].count), slot_text_pos)
                    }
                    draw_char(c, {slot_rect.x + RUNE_WIDTH * UI_SCALE, slot_rect.y + RUNE_HEIGHT * UI_SCALE}, reverse = s.selected_slot == 1)

                    left_rect := rl.Rectangle {
                        panel.rect.x, 
                        panel.rect.y, 
                        s.panels[.Base].rect.width, 
                        s.panels[.Base].rect.height,
                    }
                    conf := ListConf{
                        left_rect,
                        BG_COLOR,
                        rl.WHITE,
                        "STORAGE",
                        elements[:],
                    }
                    draw_list(conf)
                }
            case .Fps:
                fps_text := tbprintf("%v", rl.GetFPS())

                panel.rect.width = f32(len(fps_text) + 2) * RUNE_WIDTH * UI_SCALE
                panel.rect.height = FPS_MENU_HEIGHT * RUNE_HEIGHT * UI_SCALE
                if panel.active {
                    draw_border(panel.rect, BG_COLOR)
                    pos := rl.Vector2{panel.rect.x + RUNE_WIDTH * UI_SCALE, panel.rect.y + RUNE_HEIGHT * UI_SCALE}
                    draw_text(fps_text, pos)
                }
        }
    }
}

get_ore_color :: proc(ore_type: OreType) -> rl.Color {
    switch ore_type {
        case .None:     return rl.BLANK
        case .Iron:     return rl.WHITE
        case .Tungsten: return {235, 255, 235, 255}
        case .Coal:     return rl.DARKGRAY
        case .Copper:   return rl.ORANGE
        case: nucoib_panic("Unknown ore type: %v", ore_type)
    }
}

get_char :: proc(ore_type: OreType) -> u8 {
    switch ore_type {
        case .None:     return ' '
        case .Iron:     return 'I'
        case .Tungsten: return 'T'
        case .Coal:     return 'c'
        case .Copper:   return 'C'
        case: nucoib_panic("Unknown ore type: %v", ore_type)
    }
}

draw_list :: proc(conf: ListConf) {
    draw_border(conf.rect, conf.bg_color, conf.fg_color, conf.title)
    for element, i in conf.content {
        pos := rl.Vector2 {
            conf.rect.x + RUNE_WIDTH * UI_SCALE,
            conf.rect.y + f32(int(i) + 1) * RUNE_HEIGHT * UI_SCALE,
        }  
        draw_text(element.text, pos, reverse = element.reverse)
    }
}

draw_border :: proc(rect: rl.Rectangle, bg_color: rl.Color = {}, fg_color: rl.Color = rl.WHITE, title: string = "") {
    rl.DrawTexturePro(s.font_texture, s.blank_texture_rec, rect, {}, 0, bg_color)
    
    for i := 0; i < int(rect.width / RUNE_WIDTH / UI_SCALE); i += 1 {
        x := f32(i) * RUNE_WIDTH * UI_SCALE + rect.x
        upper_pos := rl.Vector2{x, rect.y}
        lower_pos := rl.Vector2{x, rect.height - RUNE_HEIGHT * UI_SCALE + rect.y}
        if (i == 0 || i == int(rect.width / RUNE_WIDTH / UI_SCALE) - 1) {
            draw_char('+', upper_pos, UI_SCALE, bg_color, fg_color)
            draw_char('+', lower_pos, UI_SCALE, bg_color, fg_color)
        } else {
            draw_char('-', upper_pos, UI_SCALE, bg_color, fg_color)
            draw_char('-', lower_pos, UI_SCALE, bg_color, fg_color)
        }
    }
    for i := 1; i < int(rect.height / RUNE_HEIGHT / UI_SCALE) - 1; i += 1 {
        y := f32(i) * RUNE_HEIGHT * UI_SCALE + rect.y
        left_pos := rl.Vector2{rect.x, y}
        right_pos := rl.Vector2{rect.width - RUNE_WIDTH * UI_SCALE + rect.x, y}
        draw_char('|', left_pos, UI_SCALE, bg_color, fg_color)
        draw_char('|', right_pos, UI_SCALE, bg_color, fg_color)
    }

    title_pos := rl.Vector2{rect.x + rect.width/2 - f32(len(title))/2 * RUNE_WIDTH * UI_SCALE , rect.y}
    draw_text(title, title_pos)
}

draw_text :: proc(text: string, pos: rl.Vector2, reverse: bool = false) {
    for i := 0; i < len(text); i += 1 {
        char_pos := rl.Vector2{f32(i) * RUNE_WIDTH * UI_SCALE, 0} + pos
        draw_char(text[i], char_pos, UI_SCALE, reverse = reverse)
    }
}

draw_sprite_pro :: proc(source: rl.Rectangle, dest: rl.Rectangle, bg_color: rl.Color, fg_color: rl.Color, reverse: bool, rotation: f32) {
    fg_color_temp, bg_color_temp := fg_color, bg_color
    if reverse do fg_color_temp, bg_color_temp = bg_color, fg_color
    if bg_color_temp.a != 0 do rl.DrawTexturePro(s.font_texture, s.blank_texture_rec, dest, {dest.width, dest.height}/2, rotation, bg_color_temp)
    if fg_color_temp.a != 0 do rl.DrawTexturePro(s.font_texture, source, dest, {dest.width, dest.height}/2, rotation, fg_color_temp) 
}

draw_char :: proc(c: u8, pos: rl.Vector2, scale: f32 = UI_SCALE, bg_color: rl.Color = BG_COLOR, fg_color: rl.Color = rl.WHITE, reverse: bool = false) {
    source := rl.Rectangle {
        x = f32(int(c - 32) % RUNE_COLS) * RUNE_WIDTH,
        y = f32(int(c - 32) / RUNE_COLS) * RUNE_HEIGHT,
        width = RUNE_WIDTH,
        height = RUNE_HEIGHT,
    }
    dest := rl.Rectangle {
        x = pos.x,
        y = pos.y,
        width = RUNE_WIDTH * scale,
        height = RUNE_HEIGHT * scale,
    } 
    fg_color_temp, bg_color_temp := fg_color, bg_color

    if reverse do fg_color_temp, bg_color_temp = bg_color, fg_color 
    if bg_color_temp.a != 0 do rl.DrawTexturePro(s.font_texture, s.blank_texture_rec, dest, {}, 0, bg_color_temp)
    if fg_color_temp.a != 0 do rl.DrawTexturePro(s.font_texture, source, dest, {}, 0, fg_color_temp) 
}

clear_temp_buffer :: proc() {
    s.temp_buffer_length = 0
}

tbprintf :: proc(str: string, args: ..any) -> string {
    stream := io.Stream{procedure = tbprintf_callback}
    begin := s.temp_buffer_length
    fmt.wprintf(stream, str, ..args, flush = false)
    return string(s.temp_buffer[begin:s.temp_buffer_length])
}

tbprintf_callback :: proc(stream_data: rawptr, mode: io.Stream_Mode, p: []u8, offset: i64, whence: io.Seek_From) -> (n: i64, err: io.Error) {
    #partial switch mode {
        case .Write:
            assert(len(p) <= len(s.temp_buffer) - s.temp_buffer_length, "Text buffer is full! Maybe you forgot to clean it?")
            copy(s.temp_buffer[s.temp_buffer_length:], p)
            s.temp_buffer_length += len(p)
            n = i64(len(p))
        case: nucoib_panic("Not supported mode: %v", mode)
    }
    return
}

print_with_color :: proc(str: string, color: rl.Color) {
    fmt.printf("\x1B[38;2;%v;%v;%vm%v\x1B[38;5;5;39;39;39m", color.r, color.g, color.b, str)
}

nucoib_log :: proc(args: ..any) {
    print_with_color("[LOG]: ", LOG_COLOR)
    fmt.print(..args)
}

nucoib_logln :: proc(args: ..any) {
    print_with_color("[LOG]: ", LOG_COLOR)
    fmt.println(..args)
}

nucoib_logf :: proc(str: string, args: ..any) {
    print_with_color("[LOG]: ", LOG_COLOR)
    fmt.printf(str, ..args)
}

nucoib_logfln :: proc(str: string, args: ..any) {
    print_with_color("[LOG]: ", LOG_COLOR)
    fmt.printfln(str, ..args)
}

nucoib_error :: proc(args: ..any) {
    print_with_color("[ERROR]: ", ERROR_COLOR)
    fmt.eprint(..args)
}

nucoib_errorln :: proc(args: ..any) {
    print_with_color("[ERROR]: ", ERROR_COLOR)
    fmt.eprintln(..args)
}

nucoib_errorf :: proc(str: string, args: ..any) {
    print_with_color("[ERROR]: ", ERROR_COLOR)
    fmt.eprintf(str, ..args)
}

nucoib_errorfln :: proc(str: string, args: ..any) {
    print_with_color("[ERROR]: ", ERROR_COLOR)
    fmt.eprintfln(str, ..args)
}

nucoib_warning :: proc(args: ..any) {
    print_with_color("[WARNING]: ", WARNING_COLOR)
    fmt.eprint(..args)
}

nucoib_warningln :: proc(args: ..any) {
    print_with_color("[WARNING]: ", WARNING_COLOR)
    fmt.eprintln(..args)
}

nucoib_warningf :: proc(str: string, args: ..any) {
    print_with_color("[WARNING]: ", WARNING_COLOR)
    fmt.eprintf(str, ..args)
}

nucoib_warningfln :: proc(str: string, args: ..any) {
    print_with_color("[WARNING]: ", WARNING_COLOR)
    fmt.eprintfln(str, ..args)
}

nucoib_panic :: proc(str: string, args: ..any, loc := #caller_location) -> ! {
    print_with_color("[PANIC]: ", PANIC_COLOR)
    fmt.eprintfln(str, ..args)
    intrinsics.trap()
}

main :: proc() {
    rl.InitWindow(s.window_width, s.window_height, "nucoib")
    rl.SetWindowState({.WINDOW_RESIZABLE})
    rl.SetTargetFPS(60)
    rl.SetExitKey(.KEY_NULL)

    err: runtime.Allocator_Error
    s.ores, err = new(Ores)
    if err != nil {
        nucoib_errorfln("Buy MORE RAM! --> %v", err)
        nucoib_errorfln("Need memory: %v bytes", size_of(Ores))
    }
    s.buildings, err = new(Buildings)
    if err != nil {
        nucoib_errorfln("Buy MORE RAM! --> %v", err)
        nucoib_errorfln("Need memory: %v bytes", size_of(Buildings))
    }

    total_size := f64(size_of(Ores) + size_of(Buildings)) / 1e6
    ores_size := f64(size_of(Ores)) / 1e6
    buildings_size := f64(size_of(Buildings)) / 1e6
    nucoib_logfln("Map size: %v Mb", total_size)
    nucoib_logfln("  - Ores: %v Mb (%.2v%%)", ores_size, ores_size / total_size * 100)
    nucoib_logfln("  - Buildings: %v Mb (%.2v%%)", buildings_size, buildings_size / total_size * 100)

    s.font_texture = rl.LoadTexture("./atlas.png")
    
    s.blank_texture_rec = {
        x = (RUNE_COLS - 1) * RUNE_WIDTH,
        y = (RUNE_ROWS - 1) * RUNE_HEIGHT,
        width = RUNE_WIDTH,
        height = RUNE_HEIGHT,
    }

    recalculate_grid_size()

    s.panels = {
        .None = {},
        .Fps = {priority = 3, anchor = {.Left, .Down}},
        .Base = {priority = 2, anchor = {.Right, .Up}},
        .Direction = {priority = 1, anchor = {.Right, .Down}, active = true},
        .Use = {priority = 0, anchor = {.Left, .Up, .Right, .Down}},
        .Stood = {priority = 4, anchor = {.Left, .Up}},
    }

    s.player.pos.x = WORLD_WIDTH / 2
    s.player.pos.y = WORLD_HEIGHT / 2

    for _ in 0..<CLUSTER_COUNT {
        tile := OreType(rand.int31_max(len(OreType)))
        cluster_generation(tile)
    }

    base_pos := Vec2i{WORLD_WIDTH, WORLD_HEIGHT} / 2 - 1
    building_ptr_at(base_pos)^ = Base{}
    s.base = &building_ptr_at(base_pos).(Base)
    for i := base_pos.x; i <= base_pos.x + 2; i += 1 {
        for j := base_pos.y; j <= base_pos.y + 2; j += 1 {
            if i == base_pos.x && j == base_pos.y do continue
            s.buildings[i][j] = Part{base_pos}
        }
    }

    for !rl.WindowShouldClose() {
        rl.BeginDrawing()
        s.dt = rl.GetFrameTime()
        input()
        update()
        draw()
        rl.EndDrawing()
    }
}
