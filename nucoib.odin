package nucoib

import "core:fmt"
import "core:math/rand"
import "core:container/queue"
import "core:slice"
import "core:io"
import "core:os"
import "core:mem"
import "base:runtime"
import "base:intrinsics"
import rl "vendor:raylib"

ATLAS_COLS             :: 18
ATLAS_ROWS             :: 7
STOOD_MENU_HEIGHT      :: 4
DIRECTION_MENU_WIDTH   :: 3
DIRECTION_MENU_HEIGHT  :: 3
FPS_MENU_WIDTH         :: 4
FPS_MENU_HEIGHT        :: 3
SLOT_MENU_WIDTH        :: 13
SLOT_MENU_HEIGHT       :: 7
WORLD_WIDTH            :: 1000
WORLD_HEIGHT           :: 1000
CLUSTER_SIZE           :: 100
CLUSTER_COUNT          :: 10000
MIN_SCALE              :: f32(1)
MAX_SCALE              :: f32(20)
ORE_SCALE              :: f32(0.5)
MOVE_COOLDOWN          :: f32(0.05)
DIGGING_COOLDOWN       :: f32(0.5)
DRILLING_TIME          :: f32(0.5) 
TRANSPORTATION_SPEED   :: f32(1)
BG_COLOR               :: rl.Color {0x20, 0x20, 0x20, 0xFF}
MAX_ORE_COUNT          :: 1000
MIN_ORE_COUNT          :: 100
SAVE_FILE_NAME         :: "save.bin"
MAX_FUEL               :: 100
SELECT_COOLDOWN        :: f32(0.15)
FUEL_TIME              :: f32(4)
WORLD_RECT             :: Rect{{0, 0}, {WORLD_WIDTH, WORLD_HEIGHT}}

Ores      :: [WORLD_WIDTH][WORLD_HEIGHT]Ore
Buildings :: [WORLD_WIDTH][WORLD_HEIGHT]Building
Vec2i     :: [2]int

Player :: struct { 
    pos: Vec2i,
}

Building :: union {
    Drill,
    Conveyor,
    Base,
    Part,
}

Rect :: struct {
    pos:  Vec2i,
    size: Vec2i,
} 

Drill :: struct {
    ores:           [dynamic]Ore,
    capacity:       u8,
    next_tile:      u8,
    drilling_timer: f32,
    fuel_time:      f32,
    direction:      Direction,
    fuel_slot:      Ore,
}

Conveyor :: struct {
    direction:               Direction,
    ore_type:                OreType,
    transportation_progress: f32,
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
    priority: int,
    rect:     Rect,
    anchor:   bit_set[Direction],
    active:   bool,
}

PanelType :: enum {
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
    pos:      Vec2i,
    size:     Vec2i,
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
    selected_ore:         int,
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
    panel_offset:         Vec2i,
    current_panel:        PanelType,
}


s := State {
    window_width  = 1280,
    window_height = 720,
    scale         = 2,
    direction     = Direction.Right,
    current_panel = PanelType(-1),
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

@(require_results)
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

@(require_results)
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
            queue.push_back(&tovisit, Vec2i{ci.x-1, ci.y})
        }
        if ci.x + 1 != WORLD_WIDTH {
            queue.push_back(&tovisit, Vec2i{ci.x+1, ci.y})
        }
        if ci.y - 1 != -1 {
            queue.push_back(&tovisit, Vec2i{ci.x, ci.y-1})
        }
        if ci.y + 1 != WORLD_HEIGHT {
            queue.push_back(&tovisit, Vec2i{ci.x, ci.y+1})
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


grid_size :: proc() -> (int, int) {
    grid_rows := int(f32(s.window_height) / (s.char_height * s.scale))
    grid_cols := int(f32(s.window_width) / (s.char_width * s.scale))
    return grid_rows, grid_cols
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
        case:
            nucoib_panic("Couldn't get resources from building: %v", B)
    }
}

input :: proc(dt: f32) {
    if rl.IsWindowResized() {
        s.window_width = rl.GetScreenWidth()
        s.window_height = rl.GetScreenHeight()
        s.grid_rows, s.grid_cols = grid_size()
    }
    
    select: if s.pressed_move > 0 {
        s.pressed_move -= dt
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
    } else {
        if rl.IsKeyDown(.RIGHT) && s.selected_slot == 0 {
            ore := Ore{OreType(s.selected_ore), 0}
            if ore.type != .Coal do break select
            if s.selected_drill.fuel_slot == {} do s.selected_drill.fuel_slot = ore 
            if s.selected_drill.fuel_slot.type == ore.type {
                if s.base.ores[ore.type] > 0 && s.selected_drill.fuel_slot.count < MAX_FUEL {
                    if rl.IsKeyDown(.LEFT_SHIFT) {
                        max := MAX_FUEL - s.selected_drill.fuel_slot.count
                        s.selected_drill.fuel_slot.count += min(s.base.ores[ore.type], 5, max)
                        s.base.ores[ore.type] -= min(s.base.ores[ore.type], 5, max)
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
        if rl.IsKeyDown(.DOWN) {
            s.selected_ore = (s.selected_ore + 1) % len(OreType)
        }  
        if rl.IsKeyDown(.LEFT) {
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
        if rl.IsKeyDown(.UP) {
            s.selected_ore = (s.selected_ore - 1) % len(OreType)
            if s.selected_ore < 0 do s.selected_ore = len(OreType) - 1
        }
        if rl.IsKeyDown(.TAB) {
            s.selected_slot = (s.selected_slot + 1) % 2
        }  
        s.pressed_move = SELECT_COOLDOWN
    }
    
    if rl.IsKeyPressed(.MINUS) {
        s.scale = max(MIN_SCALE, 0.9 * s.scale)
        s.grid_rows, s.grid_cols = grid_size()
    }
    if rl.IsKeyPressed(.EQUAL) {
        s.scale = min(1.1 * s.scale, MAX_SCALE)
        s.grid_rows, s.grid_cols = grid_size()
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
                s.buildings[x + 0][y + 0] = Drill{capacity = 20, direction = s.direction}
            }
        }
    }
    
    if rl.IsKeyPressed(.R) {
        s.direction = Direction((i32(s.direction) + 1) % (i32(max(Direction)) + 1))
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
    if rl.IsKeyPressed(.E)  {
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
    if rl.IsKeyDown(.X) {
        delete_building(s.player.pos)
    }
    if s.pressed_dig > 0 {
        s.pressed_dig -= dt
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
    if rl.IsMouseButtonDown(.LEFT) && s.current_panel == PanelType(-1) {
        mouse_pos := screen_to_grid(rl.GetMousePosition())
        
        current_panel_index := PanelType(-1)
        for panel, i in s.panels {
            if check_boundaries(mouse_pos, panel.rect) {
                if (current_panel_index == PanelType(-1) || panel.priority < s.panels[current_panel_index].priority) && panel.active {
                    current_panel_index = i
                }
            }
        }
        s.current_panel = current_panel_index
        if s.current_panel != PanelType(-1) {
            s.panel_offset = s.panels[s.current_panel].rect.pos - mouse_pos
            // Maybe fix this shit later 
            for &panel in s.panels {
                panel.priority += 1
            }
            s.panels[s.current_panel].priority = 0
        }
        nucoib_logln(current_panel_index) 
    }
    if rl.IsMouseButtonUp(.LEFT) {
        s.current_panel = PanelType(-1)
    }
}

rect_clamp :: proc(inner: ^Rect, outer: Rect) -> bit_set[Direction] {
    sides: bit_set[Direction]
    
    if inner.pos.x < outer.pos.x {
        inner.pos.x = outer.pos.x
        sides += {.Left}
    }
    if inner.pos.y < outer.pos.y {
        inner.pos.y = outer.pos.y 
        sides += {.Up}
    }
    if inner.pos.x + inner.size.x > outer.pos.x + outer.size.x {
        inner.pos.x = outer.pos.x + outer.size.x - inner.size.x   
        sides += {.Right}
    }
    if inner.pos.y + inner.size.y > outer.pos.y + outer.size.y {
        inner.pos.y = outer.pos.y + outer.size.y - inner.size.y 
        sides += {.Down}
    }
    return sides
}

update :: proc(dt: f32) {
    if s.current_panel != PanelType(-1) {
        s.panels[s.current_panel].rect.pos = screen_to_grid(rl.GetMousePosition()) + s.panel_offset
        s.panels[s.current_panel].anchor = rect_clamp(&s.panels[s.current_panel].rect, {{0, 0}, {s.grid_cols, s.grid_rows}})
    }

    for &panel in s.panels {
        switch panel.anchor {
            case {.Left}:
                panel.rect.pos.x = 0 
            case {.Up}:
                panel.rect.pos.y = 0 
            case {.Right}:
                panel.rect.pos.x = s.grid_cols - panel.rect.size.x 
            case {.Down}:
                panel.rect.pos.y = s.grid_rows - panel.rect.size.y 
            case {.Left, .Up}:
                panel.rect.pos.x = 0 
                panel.rect.pos.y = 0 
            case {.Left, .Down}:
                panel.rect.pos.x = 0 
                panel.rect.pos.y = s.grid_rows - panel.rect.size.y 
            case {.Right, .Up}:
                panel.rect.pos.x = s.grid_cols - panel.rect.size.x 
                panel.rect.pos.y = 0 
            case {.Right, .Down}:
                panel.rect.pos.x = s.grid_cols - panel.rect.size.x 
                panel.rect.pos.y = s.grid_rows - panel.rect.size.y 
            case {.Left, .Right}:
                panel.rect.pos.x = s.grid_cols/2 - panel.rect.size.x/2 
            case {.Up, .Down}:
                panel.rect.pos.y = s.grid_rows/2 - panel.rect.size.y/2 
            case {.Left, .Up, .Right, .Down}:
                panel.rect.pos.x = s.grid_cols/2 - panel.rect.size.x/2 
                panel.rect.pos.y = s.grid_rows/2 - panel.rect.size.y/2
            case {}:
            case:
                nucoib_panic("Strange direction combination: %v", panel.anchor)
        }
    }
    
    for i := 0; i < WORLD_WIDTH; i += 1 {
        for j := 0; j < WORLD_HEIGHT; j += 1 {
            switch &building in s.buildings[i][j] {
                case nil:
                case Drill: 
                    if building.fuel_time < 0 && building.fuel_slot.count > 0{
                        building.fuel_time = FUEL_TIME
                        building.fuel_slot.count -= 1
                        if building.fuel_slot.count == 0 do building.fuel_slot = {}
                    }
                    if building.fuel_time >= 0 {
                        next_ore := &s.ores[i + int(building.next_tile) % 2][j + int(building.next_tile) / 2]
                        if building.drilling_timer >= DRILLING_TIME {
                            if drill_ore_count(building) < int(building.capacity) {
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
                        if drill_ore_count(building) < int(building.capacity) {
                            building.fuel_time -= dt
                        }
                        building.drilling_timer += dt
                    
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
                                conveyor, is_conveyor := &building_ptr_at(pos).(Conveyor)
                                if is_conveyor && conveyor.ore_type == .None && drill_ore_count(building) > 0 {
                                    if conveyor.direction in perpendiculars[building.direction] do conveyor.transportation_progress = 0.7

                                    conveyor.ore_type = building.ores[0].type
                                    building.ores[0].count -= 1
                                    if building.ores[0].count <= 0 do ordered_remove(&building.ores, 0) 
                                }
                            }
                        }
                    }
                case Conveyor:
                    if building.ore_type == .None do continue
                    
                    building.transportation_progress += dt * TRANSPORTATION_SPEED
                    next_pos := offsets[building.direction] + {i, j}
                    
                    transport_ore(next_pos, &building) 
                case Base:
                case Part:
            }
        }
    }
}

transport_ore :: proc(next_pos: Vec2i, conveyor: ^Conveyor) {
    max_progress: f32 = 1
    if check_boundaries(next_pos, WORLD_RECT) { 
        switch &nb in building_ptr_at(next_pos) {
            case Drill:
                if conveyor.transportation_progress >= max_progress && conveyor.ore_type == .Coal && nb.fuel_slot.count < MAX_FUEL {
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
                    match_perpendicular := nb.direction in perpendiculars[conveyor.direction] 

                    if match_perpendicular do max_progress = 1.7

                    if conveyor.transportation_progress >= max_progress {
                        nb.ore_type = conveyor.ore_type
                        conveyor.ore_type = .None
                        conveyor.transportation_progress = 0

                        if match_perpendicular do nb.transportation_progress = 0.7
                    }
                }
            case Base:
                if conveyor.transportation_progress >= max_progress {
                    nb.ores[conveyor.ore_type] += 1  
                    conveyor.ore_type = .None
                    conveyor.transportation_progress = 0
                }
            case Part:
                transport_ore(nb.main_pos, conveyor)
        }
    }
    conveyor.transportation_progress = min(conveyor.transportation_progress, max_progress)
}

building_at :: proc(pos: Vec2i) -> Building {
    return s.buildings[pos.x][pos.y]
}

building_ptr_at :: proc(pos: Vec2i) -> ^Building {
    return &s.buildings[pos.x][pos.y]
}

check_boundaries :: proc(pos: Vec2i, rect: Rect) -> bool {
    return pos.x >= rect.pos.x && pos.x < rect.pos.x + rect.size.x && pos.y >= rect.pos.y && pos.y < rect.pos.y + rect.size.y  
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
        f32(world_pos.x - s.player.pos.x + s.grid_cols/2) * s.char_width * s.scale,
        f32(world_pos.y - s.player.pos.y + s.grid_rows/2) * s.char_height * s.scale,
    }
}

grid_to_screen :: proc(grid_pos: Vec2i) -> rl.Vector2 {
    return rl.Vector2 {
        f32(grid_pos.x) * s.char_width * s.scale,
        f32(grid_pos.y) * s.char_height * s.scale,
    }
}

screen_to_grid :: proc(screen_pos: rl.Vector2) -> Vec2i {
    return Vec2i {
        int(screen_pos.x / s.char_width / s.scale),
        int(screen_pos.y / s.char_height / s.scale),
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
        case nil:      return tbprintf("None")
        case Conveyor: return tbprintf("Conveyor_%v[%v]", b.direction, b.ore_type)
        case Base:     return tbprintf("Base")
        case Part:     return building_to_string(building_at(b.main_pos))  
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
        case Base:
            // You cannot delete the Base
        case Part:
            delete_building(building.main_pos)
    }
}

draw_building :: proc(world_pos: Vec2i, reverse: bool = false) {
    pos := world_to_screen(world_pos)
    
    switch building in building_ptr_at(world_pos) {
        case nil: 
        case Drill:
            draw_char('D', pos, 2 * s.scale, BG_COLOR, rl.MAGENTA, reverse)
            switch building.direction {
                case .Right: draw_char('>' + 0, pos + 0.5*{s.char_width * +2.2, s.char_height} * s.scale, bg_color = {})
                case .Down:  draw_char('~' + 1, pos + 0.5*{s.char_width, s.char_height * +2.1} * s.scale, bg_color = {})
                case .Left:  draw_char('<' + 0, pos + 0.5*{s.char_width * -0.2, s.char_height} * s.scale, bg_color = {})
                case .Up:    draw_char('~' + 2, pos + 0.5*{s.char_width, s.char_height * -0.1} * s.scale, bg_color = {})
            }
        case Conveyor:
            switch building.direction {
                case .Right: draw_char('>' + 0, pos, bg_color = rl.GRAY, reverse = reverse)
                case .Down:  draw_char('~' + 1, pos, bg_color = rl.GRAY, reverse = reverse)
                case .Left:  draw_char('<' + 0, pos, bg_color = rl.GRAY, reverse = reverse)
                case .Up:    draw_char('~' + 2, pos, bg_color = rl.GRAY, reverse = reverse)
            }
        case Base:
            draw_char('M', pos, 3 * s.scale, BG_COLOR, rl.BEIGE, reverse = reverse)
        case Part:
            if reverse do draw_building(building.main_pos, reverse)
    }
}

draw :: proc() {
    rl.ClearBackground(BG_COLOR)
    
    first_col := max(0, s.player.pos.x - s.grid_cols/2) + 1
    last_col  := min(s.player.pos.x + (s.grid_cols + 1)/2 - 1, WORLD_WIDTH) 
    first_row := max(0, s.player.pos.y - s.grid_rows/2) + 1
    last_row  := min(s.player.pos.y + (s.grid_rows + 1)/2 - 1, WORLD_HEIGHT)

    // Draw ores
    for i := first_col; i < last_col; i += 1 {
        for j := first_row; j < last_row; j += 1 {
            if s.buildings[i][j] != nil do continue
            
            ch_ore := get_char(s.ores[i][j].type)
            pos := world_to_screen({i, j})
            under_player := s.player.pos == {i, j}
            draw_char(ch_ore, pos, reverse = under_player)
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
            conveyor, is_conveyor := &s.buildings[i][j].(Conveyor)
            if is_conveyor && conveyor.ore_type != .None {
                pos := world_to_screen({i, j})
                
                // MAGIC STUFF, DON`T TOUCH
                ore_offset: rl.Vector2
                switch conveyor.direction {
                    case .Right:
                        ore_offset =  {
                            s.char_width * s.scale * (conveyor.transportation_progress - ORE_SCALE), 
                            s.char_height * s.scale * (0.5 - 0.5*ORE_SCALE),
                        }
                    case .Down:
                        ore_offset =  {
                            s.char_width * s.scale * (0.5 - 0.5*ORE_SCALE),
                            s.char_height * s.scale * (conveyor.transportation_progress - ORE_SCALE),
                        } 
                    case .Left: 
                        ore_offset = rl.Vector2 {
                            s.char_width * s.scale * (1 - conveyor.transportation_progress), 
                            s.char_height * s.scale * (0.5 - 0.5*ORE_SCALE),
                        }
                    case .Up:
                        ore_offset =  {
                            s.char_width * s.scale * (0.5 - 0.5*ORE_SCALE),
                            s.char_height * s.scale * (1 - conveyor.transportation_progress),
                        } 
                }

                ore_offset += pos
                c := get_char(conveyor.ore_type)
                draw_char(c, ore_offset, s.scale * ORE_SCALE, {}, rl.GOLD)
            }
        }
    }
    
    // RAMKA he is right
    draw_border({0, 0}, {s.grid_cols, s.grid_rows}, BG_COLOR)
    
    clear_temp_buffer()

    panels_indexes: [len(PanelType)]int
    for panel, i in s.panels {
        panels_indexes[i] = int(i)
    }
    
    for i := 0; i < len(panels_indexes); i += 1 {
        for j := 0; j < len(panels_indexes) - i - 1; j += 1 {
            if s.panels[PanelType(panels_indexes[j])].priority < s.panels[PanelType(panels_indexes[j + 1])].priority {
                panels_indexes[j], panels_indexes[j + 1] = panels_indexes[j + 1], panels_indexes[j]
            }
        }
    }
    
    for i in panels_indexes {
        panel := &s.panels[PanelType(i)]
        switch PanelType(i) {
            case .Base:
                elements: [len(OreType)]ListElement 
                for ore_tile in OreType {
                    elements[ore_tile] = {tbprintf("%v: %v", ore_tile, s.base.ores[ore_tile]), false}
                }
    
                str_length: int
                for element in elements {
                    if len(element.text) > str_length do str_length = len(element.text)
                }

                panel.rect.size.x = str_length + 2
                panel.rect.size.y = len(OreType) + 2
    
                if panel.active {
                    conf := ListConf{
                        panel.rect.pos,
                        panel.rect.size,
                        BG_COLOR, 
                        rl.WHITE, 
                        "MAIN",
                        elements[:],
                    }
                    draw_list(conf)
                }
            case .Direction:
                panel.rect.size = {DIRECTION_MENU_WIDTH, DIRECTION_MENU_HEIGHT}
                draw_border(panel.rect.pos, panel.rect.size, BG_COLOR, fill = true)
    
                pos := grid_to_screen(panel.rect.pos+1)
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
                panel.rect.size = {max(len(elements[0].text), len(elements[1].text), len(title)+2) + 2, STOOD_MENU_HEIGHT}
                
                if panel.active {
                    // Ore text
                    conf := ListConf {
                        panel.rect.pos,
                        panel.rect.size, 
                        BG_COLOR,
                        rl.WHITE,
                        title,
                        elements[:],
                    }
                    draw_list(conf)
                }
            case .Use:
                elements: [len(OreType)]ListElement 
                panel.rect.size = {s.panels[.Base].rect.size.x + SLOT_MENU_WIDTH - 1, s.panels[.Base].rect.size.y}
    
                // Use menu
                for ore_tile in OreType {
                    if OreType(s.selected_ore) == ore_tile {
                        elements[ore_tile] = {tbprintf("%v: %v", ore_tile, s.base.ores[ore_tile]), true}
                    } else {
                        elements[ore_tile] = {tbprintf("%v: %v", ore_tile, s.base.ores[ore_tile]), false}
                    }
                }
    
                if panel.active {
                    right_menu_pos := panel.rect.pos + {s.panels[.Base].rect.size.x-1, 0}
                    draw_border(right_menu_pos, {SLOT_MENU_WIDTH, SLOT_MENU_HEIGHT}, BG_COLOR, fill = true, title = "USE")
        
                    slot_pos := right_menu_pos + {SLOT_MENU_WIDTH/4, SLOT_MENU_HEIGHT/2} - 1
                    draw_border(slot_pos, {3, 3}, BG_COLOR, fill = true)
                    c := get_char(s.selected_drill.fuel_slot.type)
                    draw_char(c, grid_to_screen(slot_pos+1), reverse = s.selected_slot == 0)

                    bar_pos := grid_to_screen(slot_pos + {3, 0})
                    source := rl.Rectangle {
                        x = f32(int('|' - 32) % ATLAS_COLS) * s.char_width,
                        y = f32(int('|' - 32) / ATLAS_COLS) * s.char_height,
                        width = s.char_width,
                        height = s.char_height,
                    }
        
                    dest := rl.Rectangle {
                        x = bar_pos.x,
                        y = bar_pos.y,
                        width = s.char_width * s.scale,
                        height = s.char_height * s.scale * s.selected_drill.fuel_time / FUEL_TIME * 3,
                    } 
        
                    rl.DrawTexturePro(s.font_texture, source, dest, {}, 0, rl.WHITE)
                    draw_text(tbprintf("%3.v", s.selected_drill.fuel_slot.count), grid_to_screen(slot_pos + {0,3}))
        
                    slot_pos = right_menu_pos + {SLOT_MENU_WIDTH/2 + SLOT_MENU_WIDTH/4, SLOT_MENU_HEIGHT/2} - 1
                    draw_border(slot_pos, {3, 3}, BG_COLOR, fill = true)
                    if len(s.selected_drill.ores) == 0 {
                        c = get_char(.None)
                        draw_text(tbprintf("000"), grid_to_screen(slot_pos + {0,3}))
                    } else {
                        c = get_char(s.selected_drill.ores[0].type)
                        draw_text(tbprintf("%3.v", s.selected_drill.ores[0].count), grid_to_screen(slot_pos + {0,3}))
                    }
                    draw_char(c, grid_to_screen(slot_pos+1), reverse = s.selected_slot == 1)

                    // Left part
                    conf := ListConf{
                        panel.rect.pos,
                        s.panels[.Base].rect.size, 
                        BG_COLOR, 
                        rl.WHITE, 
                        "STORAGE",
                        elements[:],
                    }
                    draw_list(conf)
                }
            case .Fps:
                fps_text := tbprintf("%v", rl.GetFPS())

                panel.rect.size = {len(fps_text) + 2, FPS_MENU_HEIGHT}
                if panel.active {
                    draw_border(panel.rect.pos, panel.rect.size, BG_COLOR, fill = true)
                    pos := grid_to_screen(panel.rect.pos+1)
                    draw_text(fps_text, pos)
                }    
        }
    }
}

get_char :: proc(ore_type: OreType) -> u8 {
    c: u8
    switch ore_type {
        case .None:     c = ' '
        case .Iron:     c = 'I'
        case .Tungsten: c = 'T'
        case .Coal:     c = 'c'
        case .Copper:   c = 'C'
        case: nucoib_panic("Unknown ore type: %v", ore_type)
    }
    return c
}

draw_list :: proc(conf: ListConf) {
    draw_border(conf.pos, {conf.size.x, conf.size.y}, conf.bg_color, conf.fg_color, true, conf.title)
    for element, i in conf.content {
        pos := grid_to_screen(conf.pos + {1, int(i) + 1})
        draw_text(element.text, pos, reverse = element.reverse)
    }
}

draw_border :: proc(pos: Vec2i, size: Vec2i, bg_color: rl.Color = {}, fg_color: rl.Color = rl.WHITE, fill: bool = false, title: string = "") {
    w := size.x
    h := size.y
    
    if fill == true {
        dest := rl.Rectangle {
            x = f32(pos.x) * s.char_width * s.scale,
            y = f32(pos.y) * s.char_height * s.scale,
            width = f32(w) * s.char_width * s.scale,
            height = f32(h) * s.char_height * s.scale,
        }
        rl.DrawTexturePro(s.font_texture, s.blank_texture_rec, dest, {}, 0, bg_color)
    }
    for i := pos.x; i < w + pos.x; i += 1 {
        upper_pos := grid_to_screen({i, pos.y})
        lower_pos := grid_to_screen({i, h + pos.y - 1})
        if (i == pos.x || i == w + pos.x - 1) {
            draw_char('+', upper_pos, s.scale, bg_color, fg_color)
            draw_char('+', lower_pos, s.scale, bg_color, fg_color)
        } else {
            draw_char('-', upper_pos, s.scale, bg_color, fg_color)
            draw_char('-', lower_pos, s.scale, bg_color, fg_color)
        }
    }
    for i := pos.y + 1; i < h + pos.y - 1; i += 1 {
        left_pos := grid_to_screen({pos.x, i})
        right_pos := grid_to_screen({w + pos.x - 1, i})
        draw_char('|', left_pos, s.scale, bg_color, fg_color)
        draw_char('|', right_pos, s.scale, bg_color, fg_color)
    }

    title_pos := grid_to_screen({pos.x + w/2 - len(title)/2, pos.y})
    draw_text(title, title_pos)
}

draw_text :: proc(text: string, pos: rl.Vector2, scale: f32 = s.scale, reverse: bool = false) {
    for i := 0; i < len(text); i += 1 {
        char_pos := grid_to_screen({i, 0}) + pos
        draw_char(text[i], char_pos, scale, reverse = reverse)
    }
}

draw_char :: proc(c: u8, pos: rl.Vector2, scale: f32 = s.scale, bg_color: rl.Color = BG_COLOR, fg_color: rl.Color = rl.WHITE, reverse: bool = false) {
    source := rl.Rectangle {
        x = f32(int(c - 32) % ATLAS_COLS) * s.char_width,
        y = f32(int(c - 32) / ATLAS_COLS) * s.char_height,
        width = s.char_width,
        height = s.char_height,
    }
    dest := rl.Rectangle {
        x = pos.x,
        y = pos.y,
        width = s.char_width * scale,
        height = s.char_height * scale,
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

nucoib_log :: proc(args: ..any) {
    fmt.print("[LOG]: ")
    fmt.print(..args)
}

nucoib_logln :: proc(args: ..any) {
    fmt.print("[LOG]: ")
    fmt.println(..args)
}

nucoib_logf :: proc(str: string, args: ..any) {
    fmt.print("[LOG]: ")
    fmt.printf(str, ..args)
}

nucoib_logfln :: proc(str: string, args: ..any) {
    fmt.print("[LOG]: ")
    fmt.printfln(str, ..args)
}

nucoib_error :: proc(args: ..any) {
    fmt.eprint("[ERROR]: ")
    fmt.eprint(..args)
}

nucoib_errorln :: proc(args: ..any) {
    fmt.eprint("[ERROR]: ")
    fmt.eprintln(..args)
}

nucoib_errorf :: proc(str: string, args: ..any) {
    fmt.eprint("[ERROR]: ")
    fmt.eprintf(str, ..args)
}

nucoib_errorfln :: proc(str: string, args: ..any) {
    fmt.eprint("[ERROR]: ")
    fmt.eprintfln(str, ..args)
}

nucoib_panic :: proc(str: string, args: ..any, loc := #caller_location) -> ! {
    fmt.eprintf("[PANIC]: %v: ", loc)
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
    s.char_width = f32(int(s.font_texture.width) / ATLAS_COLS)
    s.char_height = f32(int(s.font_texture.height) / ATLAS_ROWS)

    s.blank_texture_rec = {
        x = (ATLAS_COLS - 1) * s.char_width,
        y = (ATLAS_ROWS - 1) * s.char_height,
        width = s.char_width,
        height = s.char_height,
    }
    
    s.grid_rows, s.grid_cols = grid_size()
    
    s.panels = {
        .Fps = {priority = 3, anchor = {.Left, .Down}},
        .Base = {priority = 2, anchor = {.Right, .Up}},
        .Direction = {priority = 1, anchor = {.Right, .Down}, active = true},
        .Use = {priority = 0, anchor = {.Left, .Up, .Right, .Down}},
        .Stood = {priority = 4, anchor = {.Left, .Up}},
    }

    s.player.pos.x = WORLD_WIDTH / 2
    s.player.pos.y = WORLD_HEIGHT / 2
    
    for _ in 0..<CLUSTER_COUNT {
        max_tile := i32(max(OreType)) + 1
        tile := OreType(rand.int31_max(max_tile))
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
        
        dt := rl.GetFrameTime()

        input(dt)
        update(dt)
        draw()
              
        rl.EndDrawing()
    }    
}
