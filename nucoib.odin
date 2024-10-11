package nucoib

import "core:fmt"
import "core:strings"
import "core:math"
import "core:math/rand"
import "core:container/queue"
import "core:slice"
import "core:io"
import "base:runtime"
import rl "vendor:raylib"

ATLAS_COLS             :: 18
ATLAS_ROWS             :: 7
STOOD_MENU_HEIGHT      :: 5
DIRECTION_MENU_HEIGHT  :: 3
DIRECTION_MENU_WIDTH   :: 3
FPS_MENU_HEIGHT        :: 3
FPS_MENU_WIDTH         :: 4
WORLD_WIDTH            :: 1000
WORLD_HEIGHT           :: 1000
CLUSTER_SIZE           :: 100
CLUSTER_COUNT          :: 10000
MIN_SCALE              :: f32(1)
MAX_SCALE              :: f32(20)
ORE_SCALE              :: f32(0.5)
ZOOM_COOLDOWN          :: f32(0.0)
MOVE_COOLDOWN          :: f32(0.05)
DRILLING_TIME          :: f32(0.5) 
TRANSPORTATION_SPEED   :: f32(1)
BG_COLOR               :: rl.Color {0x20, 0x20, 0x20, 0xFF}
MAX_ORE_COUNT          :: 1000
MIN_ORE_COUNT          :: 100

World     :: [WORLD_WIDTH][WORLD_HEIGHT]Ore
Buildings :: [WORLD_WIDTH][WORLD_HEIGHT]BuildingTile
Vec2i     :: [2]int

Player :: struct { 
    pos: Vec2i,
}

BuildingTile :: union {
    Drill,
    Conveyor,
    Base,
    Part,
}

Drill :: struct {
    ores:           [dynamic]Ore,
    capacity:       int,
    drilling_timer: f32,
    next_tile:      int,
    direction:      Direction,
}

Conveyor :: struct {
    direction:               Direction,
    ore_type:                OreType,
    capacity:                int,
    transportation_progress: f32,
}

Base :: struct {
    ores: [OreType]int,
}

Part :: struct {
    main_pos: Vec2i
}

OreType :: enum u8 {
    None,
    Iron,
    Tungsten,
    Coal,
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

Direction :: enum {
   Right,
   Down,
   Left,
   Up, 
}

State :: struct {
    world:                ^World,
    buildings:            ^Buildings,
    base:                 ^Base, 
    player:               Player,
    font_texture:         rl.Texture2D,
    char_width:           f32,
    char_height:          f32,
    grid_rows:            int,
    grid_cols:            int,
    pressed_move:         f32,
    pressed_zoom:         f32,
    stood_menu:           bool,
    base_menu:            bool,
    fps_menu:             bool,
    count_clusters_sizes: [CLUSTER_SIZE + 1]int,
    temp_buffer:          [512]u8,
    temp_buffer_length:   int,
    window_width:         i32,
    window_height:        i32,
    scale:                f32,
    direction:            Direction,
}

s := State {
    window_width  = 1280,
    window_height = 720,
    scale         = 2,
    direction     = Direction.Right,
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

cluster_generation :: proc(tile: OreType) {
    count_useless := 0
    count_usefull := 0
    cx := rand.int_max(WORLD_WIDTH)
    cy := rand.int_max(WORLD_HEIGHT)

    tovisit: queue.Queue(Vec2i)
    visited: [dynamic]Vec2i
    queue.push_back(&tovisit, Vec2i{cx, cy})
    
    for queue.len(tovisit) > 0 {
        ci := queue.pop_front(&tovisit)
         
        if slice.contains(visited[:], ci) do continue
        append(&visited, ci)
        
        // y = -x/10+1
        r := rand.float32()
        y := -f32(count_useless) / CLUSTER_SIZE + 1
        count_useless += 1
        if r >= y do continue

        // y = -log(x/10)
        // if rand.float32() >= -math.log10(f32(count_useless)/CLUSTER_SIZE) do continue      
        
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
        min := int(y * MIN_ORE_COUNT)
        max := int(y * MAX_ORE_COUNT)
        count := rand.int_max(max - min) + min
        
        s.world[ci.x][ci.y] = {tile, count}
        count_usefull += 1
    }
    
    s.count_clusters_sizes[count_usefull] += 1
    delete(visited)
    queue.destroy(&tovisit)
}


grid_size :: proc() -> (int, int) {
    grid_rows := int(f32(s.window_height) / (s.char_height * s.scale))
    grid_cols := int(f32(s.window_width) / (s.char_width * s.scale))
    return grid_rows, grid_cols
}

input :: proc(dt: f32) {
    if s.pressed_move > 0 {
        s.pressed_move -= dt
    } else {
        if rl.IsKeyDown(rl.KeyboardKey.RIGHT) && s.player.pos.x < WORLD_WIDTH - 1 {
            s.player.pos.x += 1
        }
        if rl.IsKeyDown(rl.KeyboardKey.DOWN) && s.player.pos.y < WORLD_HEIGHT - 1 {
            s.player.pos.y += 1
        }  
        if rl.IsKeyDown(rl.KeyboardKey.LEFT) && s.player.pos.x > 0 {
            s.player.pos.x -= 1 
        }
        if rl.IsKeyDown(rl.KeyboardKey.UP) && s.player.pos.y > 0 {
            s.player.pos.y -= 1
        }
        s.pressed_move = MOVE_COOLDOWN      
    }
    
    if s.pressed_zoom > 0 {
        s.pressed_zoom -= dt 
    } else {
        if rl.IsKeyPressed(rl.KeyboardKey.MINUS) {
            s.scale = max(MIN_SCALE, s.scale*0.9)
            s.grid_rows, s.grid_cols = grid_size()
        }
        if rl.IsKeyPressed(rl.KeyboardKey.EQUAL) {
            s.scale = min(s.scale*1.1, MAX_SCALE)
            s.grid_rows, s.grid_cols = grid_size()
        }
        s.pressed_zoom = ZOOM_COOLDOWN
    }
    
    drill: if rl.IsKeyDown(rl.KeyboardKey.D) {
        if check_boundaries(s.player.pos + 1) {
            x := s.player.pos.x
            y := s.player.pos.y
            for i := x; i < x + 2; i += 1 {
                for j := y; j < y + 2; j += 1 {
                     if s.buildings[i][j] != nil do break drill
                }
            } 
            
            s.buildings[x + 1][y + 0] = Part{s.player.pos}
            s.buildings[x + 1][y + 1] = Part{s.player.pos}
            s.buildings[x + 0][y + 1] = Part{s.player.pos}
            s.buildings[x + 0][y + 0] = Drill{capacity = 20, direction = s.direction}
        }
    }
    
    if rl.IsKeyPressed(rl.KeyboardKey.R) {
        s.direction = Direction((i32(s.direction) + 1) % (i32(max(Direction)) + 1))
    }
    if rl.IsKeyPressed(rl.KeyboardKey.GRAVE) {
        s.stood_menu = !s.stood_menu
    }
    if rl.IsKeyPressed(rl.KeyboardKey.I) {
        s.base_menu = !s.base_menu
    }
    if rl.IsKeyPressed(rl.KeyboardKey.F1) {
        s.fps_menu = !s.fps_menu
    }
    if rl.IsKeyDown(rl.KeyboardKey.C) {
        building := &s.buildings[s.player.pos.x][s.player.pos.y]
        conveyor, ok := building.(Conveyor)
        
        if (ok && conveyor.direction != s.direction) || building^ == nil { 
            building^ = Conveyor{direction = s.direction}
        }
    }
    if rl.IsKeyDown(rl.KeyboardKey.X) {
        delete_building(s.player.pos)        
    }
}

update :: proc(dt: f32) {
    for i := 0; i < WORLD_WIDTH; i += 1 {
        for j := 0; j < WORLD_HEIGHT; j += 1 {
            switch &building in s.buildings[i][j] {
                case nil:
                case Drill: 
                    next_ore := &s.world[i + building.next_tile % 2][j + building.next_tile / 2]
                    
                    if building.drilling_timer >= DRILLING_TIME {
                        if drill_ore_count(building) < building.capacity {
                            if next_ore.type != .None {
                                if len(building.ores) != 0 && building.ores[len(building.ores) - 1].type == next_ore.type {
                                    building.ores[len(building.ores) - 1].count += 1
                                } else {
                                    append(&building.ores, Ore{next_ore.type, 1})
                                }
                                
                                next_ore.count -= 1
                                if next_ore.count <= 0 {
                                    next_ore^ = {}
                                }
                            } 
                            building.next_tile = (building.next_tile + 1) % 4
                        } 
                        building.drilling_timer = 0
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
                        if check_boundaries(pos) {
                            conveyor, is_conveyor := &s.buildings[pos.x][pos.y].(Conveyor)
                            if is_conveyor && conveyor.ore_type == .None && drill_ore_count(building) > 0 {
                                if conveyor.direction in perpendiculars[building.direction] do conveyor.transportation_progress = 0.7

                                conveyor.ore_type = building.ores[0].type
                                building.ores[0].count -= 1
                                if building.ores[0].count <= 0 do ordered_remove(&building.ores, 0) 
                            }
                        }
                    }
                case Conveyor:
                    if building.ore_type == .None do continue
                    
                    building.transportation_progress += dt * TRANSPORTATION_SPEED
                    next_pos := Vec2i{i, j} + offsets[building.direction]
                    max_progress: f32 = 1
                    
                    if check_boundaries(next_pos) { 
                        switch &next_building in s.buildings[next_pos.x][next_pos.y] {
                            case Drill:
                            case Conveyor:
                                if next_building.ore_type == .None && next_building.direction != opposite[building.direction] {
                                    match_perpendicular := next_building.direction in perpendiculars[building.direction] 
                            
                                    if match_perpendicular do max_progress = 1.7
                            
                                    if building.transportation_progress >= max_progress {
                                        next_building.ore_type = building.ore_type
                                        building.ore_type = .None
                                        building.transportation_progress = 0
                            
                                        if match_perpendicular do next_building.transportation_progress = 0.7
                                    }
                                }
                            case Base:
                                if building.transportation_progress >= max_progress {
                                    next_building.ores[building.ore_type] += 1  
                                    building.ore_type = .None
                                    building.transportation_progress = 0
                                }
                            case Part:
                                if base, ok := &s.buildings[next_building.main_pos.x][next_building.main_pos.y].(Base); ok  {
                                    if building.transportation_progress >= max_progress {
                                        base.ores[building.ore_type] += 1  
                                        building.ore_type = .None
                                        building.transportation_progress = 0
                                    }
                                } 
                        }
                    }
                    building.transportation_progress = min(building.transportation_progress, max_progress)
                case Base:
                case Part:
            }
        }
    }
}

check_boundaries :: proc(pos: Vec2i) -> bool {
    return pos.x >= 0 && pos.x < WORLD_WIDTH && pos.y >= 0 && pos.y < WORLD_HEIGHT  
}

drill_ore_count :: proc(drill: Drill) -> int {
    count: int = 0
    for ore in drill.ores {
        count += ore.count
    }
    return count
}

string_building :: proc(building: BuildingTile) -> string {
    switch building in building {
        case Drill:    
            if len(building.ores) == 0 {
                return tbprintf("Drill[:]")
            } else {
                return tbprintf("Drill[%v:%v]", building.ores[0].type, building.ores[0].count)
            }
        case nil:      return tbprintf("None")
        case Conveyor: return tbprintf("Conveyor_%v[%v]", building.direction, building.ore_type)
        case Base:     return tbprintf("Base")
        case Part:     return string_building(s.buildings[building.main_pos.x][building.main_pos.y])  
        case:                 panic(fmt.aprintf("Unknown building type %v", building))
    }
}

delete_building :: proc(pos: Vec2i) {
    switch building in s.buildings[pos.x][pos.y] {
        case nil:
        case Drill:
            s.buildings[pos.x+0][pos.y+0] = {}
            s.buildings[pos.x+1][pos.y+0] = {}
            s.buildings[pos.x+1][pos.y+1] = {}
            s.buildings[pos.x+0][pos.y+1] = {}
        case Conveyor:
            s.buildings[pos.x][pos.y] = {}
        case Base:
            // You cannot delete the Base
        case Part:
            delete_building(building.main_pos)
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
            ch_ore: u8
            switch s.world[i][j].type {
                case .None:     continue
                case .Iron:     ch_ore = 'I'
                case .Tungsten: ch_ore = 'T'
                case .Coal:     ch_ore = 'C'
                case: panic(fmt.aprintf("Unknown ore type: %v", s.world[i][j]))
            }
            
            pos := rl.Vector2 {
                f32(i - s.player.pos.x + s.grid_cols/2) * s.char_width * s.scale,
                f32(j - s.player.pos.y + s.grid_rows/2) * s.char_height * s.scale
            }

            draw_char(ch_ore, pos, s.scale)
        }
    }

    // Draw buildings background 
    for i := first_col; i < last_col; i += 1 {
        for j := first_row; j < last_row; j += 1 {
            pos := rl.Vector2 {
                f32(i - s.player.pos.x + s.grid_cols/2) * s.char_width * s.scale,
                f32(j - s.player.pos.y + s.grid_rows/2) * s.char_height * s.scale
            }
            dest := rl.Rectangle {
                x = pos.x,
                y = pos.y,
                width = s.char_width * s.scale,
                height = s.char_height * s.scale,
            }
            
            switch building in s.buildings[i][j] {
                case nil: 
                case Drill: 
                    dest := rl.Rectangle {
                        x = pos.x,
                        y = pos.y,
                        width = s.char_width * s.scale * 2,
                        height = s.char_height * s.scale * 2,
                    }
                    rl.DrawRectangleRec(dest, BG_COLOR)
                case Conveyor:
                    rl.DrawRectangleRec(dest, rl.DARKGRAY)
                case Base:
                    dest := rl.Rectangle {
                        x = pos.x,
                        y = pos.y,
                        width = s.char_width * s.scale * 3,
                        height = s.char_height * s.scale * 3,
                    }
                    rl.DrawRectangleRec(dest, BG_COLOR)
                case Part:
            }
        }
    }

    // Draw buildings
    for i := first_col; i < last_col; i += 1 {
        for j := first_row; j < last_row; j += 1 {
            pos := rl.Vector2 {
                f32(i - s.player.pos.x + s.grid_cols/2) * s.char_width * s.scale,
                f32(j - s.player.pos.y + s.grid_rows/2) * s.char_height * s.scale
            }
    
            switch building in s.buildings[i][j] {
                case nil: 
                case Drill: 
                    draw_char('D', pos + 0.375*{s.char_width, s.char_height} * s.scale, 1.25*s.scale, rl.MAGENTA)
                    switch building.direction {
                        case .Right: draw_char('>',   pos + 0.5*{s.char_width * 2.2, s.char_height} * s.scale, s.scale)
                        case .Down:  draw_char('~' + 1, pos + 0.5*{s.char_width, s.char_height * 2.1} * s.scale, s.scale)
                        case .Left:  draw_char('<',   pos + 0.5*{s.char_width * -0.2, s.char_height} * s.scale, s.scale)
                        case .Up:    draw_char('~' + 2, pos + 0.5*{s.char_width, s.char_height * -0.1} * s.scale, s.scale)
                    }
                case Conveyor:
                    switch building.direction {
                        case .Right: draw_char('>', pos, s.scale)
                        case .Down:  draw_char('~' + 1, pos, s.scale)
                        case .Left:  draw_char('<', pos, s.scale)
                        case .Up:    draw_char('~' + 2, pos, s.scale)
                    }
                case Base:
                    draw_char('M', pos, 3 * s.scale, rl.BEIGE)
                case Part:
            }
        }
    }

    // Draw on conveyor
    for i := first_col; i < last_col; i += 1 {
        for j := first_row; j < last_row; j += 1 {
            conveyor, is_conveyor := &s.buildings[i][j].(Conveyor)
            if is_conveyor && conveyor.ore_type != .None {
                pos := rl.Vector2 {
                    f32(i - s.player.pos.x + s.grid_cols/2) * s.char_width * s.scale,
                    f32(j - s.player.pos.y + s.grid_rows/2) * s.char_height * s.scale
                }
                
                ore_offset: rl.Vector2

                // MAGIC STUFF, DON`T TOUCH
                switch conveyor.direction {
                    case .Right:
                        ore_offset =  {
                            s.char_width * s.scale * (conveyor.transportation_progress - ORE_SCALE), 
                            s.char_height * s.scale * (0.5 - 0.5*ORE_SCALE)
                        }
                    case .Down:
                        ore_offset =  {
                            s.char_width * s.scale * (0.5 - 0.5*ORE_SCALE),
                            s.char_height * s.scale * (conveyor.transportation_progress - ORE_SCALE)
                        } 
                    case .Left: 
                        ore_offset = rl.Vector2 {
                            s.char_width * s.scale * (1 - conveyor.transportation_progress), 
                            s.char_height * s.scale * (0.5 - 0.5*ORE_SCALE)
                        }
                    case .Up:
                        ore_offset =  {
                            s.char_width * s.scale * (0.5 - 0.5*ORE_SCALE),
                            s.char_height * s.scale * (1 - conveyor.transportation_progress) 
                        } 
                }

                ore_offset += pos
                c: u8
                #partial switch conveyor.ore_type {
                    case .Iron:     c = 'I'
                    case .Tungsten: c = 'T'
                    case .Coal:     c = 'C'
                    case: panic(fmt.aprintf("Unknown ore type: %v", conveyor.ore_type))
                }

                draw_char(c, ore_offset, s.scale * ORE_SCALE, rl.GOLD)
            }
        }
    }

    // PLAYER
    player_pos := rl.Vector2 {
        f32(s.grid_cols/2) * s.char_width * s.scale,
        f32(s.grid_rows/2) * s.char_height * s.scale
    }
    rl.DrawRectangleV(player_pos, {s.char_width, s.char_height} * s.scale, BG_COLOR)
    draw_char('@', player_pos, s.scale, rl.VIOLET)
        
    // RAMKA he is right
    draw_border(0, 0, s.grid_cols, s.grid_rows, BG_COLOR, fill = .Partial)

    // Direction menu 
    if s.grid_cols > DIRECTION_MENU_WIDTH && s.grid_rows > DIRECTION_MENU_HEIGHT {
        draw_border(s.grid_cols - DIRECTION_MENU_HEIGHT, s.grid_rows - DIRECTION_MENU_HEIGHT, DIRECTION_MENU_WIDTH, DIRECTION_MENU_HEIGHT, BG_COLOR, fill = .All)
        
        pos := rl.Vector2 {
            f32(s.grid_cols - 2) * s.char_width, 
            f32(s.grid_rows - 2) * s.char_height
        }
        
        switch s.direction {
            case .Right: draw_char('>', pos * s.scale, s.scale, rl.SKYBLUE)
            case .Down:  draw_char('~' + 1, pos * s.scale, s.scale, rl.SKYBLUE)
            case .Left:  draw_char('<', pos * s.scale, s.scale, rl.SKYBLUE)
            case .Up:    draw_char('~' + 2, pos * s.scale, s.scale, rl.SKYBLUE)
        }
    }
    
    clear_temp_buffer()
    
    // Base menu
    str_arr: [OreType]string 
    for ore_tile in OreType {
        str_arr[ore_tile] = tbprintf("%v: %v", ore_tile, s.base.ores[ore_tile])
    }
    str_length: int
    for str in str_arr {
        if len(str) > str_length do str_length = len(str)
    }

    base_menu_width := str_length + 2
    base_menu_height := int(max(OreType)) + 3
    
    if s.grid_cols > base_menu_width && s.grid_rows > base_menu_height && s.base_menu {
        draw_border(s.grid_cols-base_menu_width, 0, base_menu_width, base_menu_height, BG_COLOR, fill = .All)
        for str, i in str_arr {
            pos := rl.Vector2 {
                f32(s.grid_cols - str_length - 1) * s.char_width,
                f32(int(i) + 1) * s.char_height 
            } 
            draw_text(str, pos * s.scale, s.scale)
        }
    }
    
    // Stood menu
    text_stood_menu := "STOOD ON:"
    text_building := string_building(s.buildings[s.player.pos.x][s.player.pos.y]) 

    text_ore: string
    ore := &s.world[s.player.pos.x][s.player.pos.y]
    #partial switch ore.type {
        case .None:
            text_ore = tbprintf("None")
        case: 
            text_ore = tbprintf("%v: %v", ore.type, ore.count)
    }
    stood_menu_width := max(len(text_stood_menu), len(text_building), len(text_ore)) + 2
    
    if s.grid_rows > STOOD_MENU_HEIGHT && s.grid_cols > stood_menu_width && s.stood_menu {
        // Ore text
        draw_border(0, 0, stood_menu_width, STOOD_MENU_HEIGHT, BG_COLOR, fill = .All)
        draw_text(text_stood_menu, {s.char_width, s.char_height*1} * s.scale, s.scale)
        draw_text(text_ore,        {s.char_width, s.char_height*2} * s.scale, s.scale)
        draw_text(text_building,   {s.char_width, s.char_height*3} * s.scale, s.scale)
    }

    // DrawFPS
    fps_text := tbprintf("%v", rl.GetFPS())
    fps_menu_width := len(tbprintf(fps_text)) + 2
    if s.grid_rows > FPS_MENU_HEIGHT && s.grid_cols > fps_menu_width && s.fps_menu {
        draw_border(0, s.grid_rows-FPS_MENU_HEIGHT, fps_menu_width, FPS_MENU_HEIGHT, BG_COLOR, fill = .All)
        draw_text(fps_text, {1, f32(s.grid_rows) - 2} * {s.char_width, s.char_height} * s.scale, s.scale )
    }
}

draw_border :: proc(x, y, w, h: int, bg_color: rl.Color = {}, fg_color: rl.Color = rl.WHITE, fill: Fill = .None) {
    if fill == .All {
        dest := rl.Rectangle {
            x = f32(x) * s.char_width * s.scale,
            y = f32(y) * s.char_height * s.scale,
            width = f32(w) * s.char_width * s.scale,
            height = f32(h) * s.char_height * s.scale,
        }
        
        rl.DrawRectangleRec(dest, bg_color)
    }
    if fill == .Partial {
        dest := rl.Rectangle {
            x = f32(x) * s.char_width * s.scale,
            y = f32(y) * s.char_height * s.scale,
            width = f32(w) * s.char_width * s.scale,
            height = s.char_height * s.scale,
        }
        rl.DrawRectangleRec(dest, bg_color)
        
        dest = rl.Rectangle {
            x = f32(x) * s.char_width * s.scale,
            y = f32(y) * s.char_height * s.scale,
            width = s.char_width * s.scale,
            height = f32(h) * s.char_height * s.scale,
        }
        rl.DrawRectangleRec(dest, bg_color)
        
        dest = rl.Rectangle {
            x = (f32(x) + f32(w) - 1) * s.char_width * s.scale,
            y = f32(y) * s.char_height * s.scale,
            width = s.char_width * s.scale,
            height = f32(h) * s.char_height * s.scale,
        }
        rl.DrawRectangleRec(dest, bg_color)
        
        dest = rl.Rectangle {
            x = f32(x) * s.char_width * s.scale,
            y = (f32(y) + f32(h) - 1)* s.char_height * s.scale,
            width = f32(w) * s.char_width * s.scale,
            height = s.char_height * s.scale,
        }
        rl.DrawRectangleRec(dest, bg_color)
    }
    for i := x; i < w + x; i += 1 {
        xw := f32(i) * s.char_width * s.scale
        upper_pos := rl.Vector2 { xw, f32(y) * s.char_height * s.scale }
        lower_pos := rl.Vector2 { xw, f32(h + y - 1) * s.char_height * s.scale }
        if (i == x || i == w + x - 1) {
            draw_char('+', upper_pos, s.scale, fg_color)
            draw_char('+', lower_pos, s.scale, fg_color)
        } else {
            draw_char('-', upper_pos, s.scale, fg_color)
            draw_char('-', lower_pos, s.scale, fg_color)
        }
    }
    for i := y + 1; i < h + y - 1; i += 1 {
        yw := f32(i) * s.char_height * s.scale
        left_pos := rl.Vector2 { f32(x) * s.char_width * s.scale , yw }
        right_pos := rl.Vector2 { f32(w + x - 1) * s.char_width * s.scale, yw }
        draw_char('|', left_pos, s.scale, fg_color)
        draw_char('|', right_pos, s.scale, fg_color)
    }
}

draw_text :: proc(text: string, pos: rl.Vector2, scale: f32) {
    for i := 0; i < len(text); i += 1 {
        char_pos := rl.Vector2 {
            f32(i) * s.char_width * scale + pos.x,
            pos.y,
        }
        draw_char(text[i], char_pos, scale)
    }
}

draw_char :: proc(c: u8, pos: rl.Vector2, scale: f32, fg_color: rl.Color = rl.WHITE) {
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
    rl.DrawTexturePro(s.font_texture, source, dest, {}, 0, fg_color) 
}

clear_temp_buffer :: proc() {
    s.temp_buffer_length = 0
}

tbprintf :: proc(str: string, args: ..any) -> string {
    stream := io.Stream {procedure = tbprintf_callback}
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
        case: fmt.panicf("Not supported mode: %v", mode)
    }
    return
}

main :: proc() {
    rl.InitWindow(s.window_width, s.window_height, "nucoib")
    rl.SetWindowState({.WINDOW_RESIZABLE})
    rl.SetTargetFPS(60)
    
    err: runtime.Allocator_Error
    s.world, err = new(World)
    if err != nil {
        fmt.println("Buy MORE RAM! --> ", err)
        fmt.println("Need memory: ", size_of(World), "Bytes")
    }
    s.buildings, err = new(Buildings)
    if err != nil {
        fmt.println("Buy MORE RAM! --> ", err)
        fmt.println("Need memory: ", size_of(Buildings), "Bytes")
    }
    
    fmt.println("Map size: ", size_of(World) + size_of(Buildings), "Bytes")
    
    s.font_texture = rl.LoadTexture("./atlas.png")
    s.char_width = f32(int(s.font_texture.width) / ATLAS_COLS)
    s.char_height = f32(int(s.font_texture.height) / ATLAS_ROWS)
    
    s.grid_rows, s.grid_cols = grid_size()

    s.player.pos.x = WORLD_WIDTH / 2
    s.player.pos.y = WORLD_HEIGHT / 2
    
    for i in 0..<CLUSTER_COUNT {
        max_tile := i32(max(OreType)) + 1
        tile := OreType(rand.int31_max(max_tile))
        cluster_generation(tile)
    }

    base_pos_x := WORLD_WIDTH / 2 - 1
    base_pos_y := WORLD_HEIGHT / 2 - 1
    
    s.buildings[base_pos_x][base_pos_y] = Base{}
    s.base = &s.buildings[base_pos_x][base_pos_y].(Base)
    
    for i := base_pos_x; i <= base_pos_x + 2; i += 1 {
        for j := base_pos_y; j <= base_pos_y + 2; j += 1 {
            if i == base_pos_x && j == base_pos_y do continue
            s.buildings[i][j] = Part{{base_pos_x, base_pos_y}}
        }
    } 
    
    for !rl.WindowShouldClose() {
        rl.BeginDrawing()
        
        if rl.IsWindowResized() {
            s.window_width = rl.GetScreenWidth()
            s.window_height = rl.GetScreenHeight()

            s.grid_rows, s.grid_cols = grid_size()
        }
        
        dt := rl.GetFrameTime()
        
        input(dt)
        update(dt)
        draw()
              
        rl.EndDrawing()
    }    
}
    
