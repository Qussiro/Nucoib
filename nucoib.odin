package nucoib

import "core:fmt"
import "core:strings"
import "core:math"
import "core:math/rand"
import "core:container/queue"
import "core:slice"
import "base:runtime"
import rl "vendor:raylib"

ATLAS_COLS           :: 18
ATLAS_ROWS           :: 7
STOOD_MENU_HEIGHT    :: 5
STOOD_MENU_WIDTH     :: 17
WORLD_WIDTH          :: 1000
WORLD_HEIGHT         :: 1000
CLUSTER_SIZE         :: 100
CLUSTER_COUNT        :: 10000
MIN_SCALE            :: f32(1)
MAX_SCALE            :: f32(20)
ORE_SCALE            :: f32(0.5)
ZOOM_COOLDOWN        :: f32(0.0)
MOVE_COOLDOWN        :: f32(0.05)
DRILLING_TIME        :: f32(0.5) 
TRANSPORTATION_SPEED :: f32(1)
BG_COLOR             :: rl.Color {0x20, 0x20, 0x20, 0xFF}

OFFSETS :: [Direction][2]int {
    .Right = {1, 0},
    .Down  = {0, 1},
    .Left  = {-1, 0},
    .Up    = {0, -1},
}
PERPENDICULARS :: [Direction]bit_set[Direction] {
    .Right = {.Up, .Down},
    .Down  = {.Left, .Right},
    .Left  = {.Up, .Down},
    .Up    = {.Left, .Right},
}
OPPOSITE :: [Direction]Direction {
    .Right = .Left,
    .Left  = .Right,
    .Down  = .Up,
    .Up    = .Down,
}

World :: [WORLD_WIDTH][WORLD_HEIGHT]OreTile
Buildings :: [WORLD_WIDTH][WORLD_HEIGHT]BuildingTile

Player :: struct { 
    x: int,
    y: int,
}

Drill :: struct {
    ores:           [dynamic]Ore,
    capacity:       int,
    drilling_timer: f32,
    next_tile:      int,
    direction:      Direction,
}

Ore :: struct {
    type:  OreTile,
    count: int,
}

Conveyor :: struct {
    direction:               Direction,
    ore_type:                OreTile,
    capacity:                int,
    transportation_progress: f32,
}

BuildingTile :: union {
    Drill,
    Conveyor,
    Part,
}

Part :: struct {
    main_pos: [2]int
}

OreTile :: enum u8 {
    None,
    Iron,
    Tungsten,
    Coal,
}

Direction :: enum {
   Right,
   Down,
   Left,
   Up, 
}

Item :: struct {
    pos: rl.Vector2,
    ore: OreTile,
}

State :: struct {
    world:                ^World,
    buildings:            ^Buildings,
    player:               Player,
    font_texture:         rl.Texture2D,
    char_width:           f32,
    char_height:          f32,
    grid_rows:            int,
    grid_cols:            int,
    pressed_move:         f32,
    pressed_zoom:         f32,
    stood_menu:           bool,
    count_clusters_sizes: [CLUSTER_SIZE + 1]int,
    text_buffer:          [512]u8,
    window_width:         i32,
    window_height:        i32,
    scale:                f32,
    direction:            Direction,
    items:                [dynamic]Item,
}

s := State {
    window_width  = 1280,
    window_height = 720,
    scale         = 2,
    direction     = Direction.Right,
} 

cluster_generation :: proc(tile: OreTile) {
    Point :: [2]i32
    
    count_useless := 0
    count_usefull := 0
    cx := rand.int31_max(WORLD_WIDTH)
    cy := rand.int31_max(WORLD_HEIGHT)

    tovisit: queue.Queue(Point)
    visited: [dynamic]Point
    queue.push_back(&tovisit, Point{cx, cy})
    
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
            queue.push_back(&tovisit, Point{ci.x-1, ci.y})
        }
        if ci.x + 1 != WORLD_WIDTH {
            queue.push_back(&tovisit, Point{ci.x+1, ci.y})
        }
        if ci.y - 1 != -1 {
            queue.push_back(&tovisit, Point{ci.x, ci.y-1})
        }
        if ci.y + 1 != WORLD_HEIGHT {
            queue.push_back(&tovisit, Point{ci.x, ci.y+1})
        }
        s.world[ci.x][ci.y] = tile
        count_usefull += 1
    }
    
    s.count_clusters_sizes[count_usefull] += 1
    delete(visited)
    queue.destroy(&tovisit)
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

grid_size :: proc() -> (int, int) {
    grid_rows := int(f32(s.window_height) / (s.char_height * s.scale))
    grid_cols := int(f32(s.window_width) / (s.char_width * s.scale))
    return grid_rows, grid_cols
}

input :: proc(dt: f32) {
    if s.pressed_move > 0 do s.pressed_move -= dt
    else {
        if rl.IsKeyDown(rl.KeyboardKey.UP) && s.player.y > 0 {
            s.player.y -= 1
        }
        if rl.IsKeyDown(rl.KeyboardKey.RIGHT) && s.player.x < WORLD_WIDTH - 1 {
            s.player.x += 1
        }
        if rl.IsKeyDown(rl.KeyboardKey.LEFT) && s.player.x > 0 {
            s.player.x -= 1 
        }
        if rl.IsKeyDown(rl.KeyboardKey.DOWN) && s.player.y < WORLD_HEIGHT - 1 {
            s.player.y += 1
        }  
        s.pressed_move = MOVE_COOLDOWN      
    }
    
    if s.pressed_zoom > 0 do s.pressed_zoom -= dt
    else {
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
        player_pos: [2]int = {s.player.x, s.player.y}
        
        if check_boundaries(player_pos+1) {
            for i := s.player.x; i < s.player.x + 2; i += 1 {
                for j := s.player.y; j < s.player.y + 2; j += 1 {
                     if s.buildings[i][j] != nil do break drill
                }
            } 
            
            s.buildings[s.player.x+1][s.player.y] = Part{player_pos}
            s.buildings[s.player.x+1][s.player.y+1] = Part{player_pos}
            s.buildings[s.player.x][s.player.y+1] = Part{player_pos}
            
            s.buildings[s.player.x][s.player.y] = Drill{capacity = 20, direction = s.direction}
        }
    }
    
    if rl.IsKeyPressed(rl.KeyboardKey.R) {
        s.direction = Direction((i32(s.direction) + 1) % (i32(max(Direction)) + 1))
    }
    if rl.IsKeyPressed(rl.KeyboardKey.GRAVE) {
        s.stood_menu = !s.stood_menu
    }
    if rl.IsKeyDown(rl.KeyboardKey.C) {
        conveyor, ok := s.buildings[s.player.x][s.player.y].(Conveyor)
        if (ok && conveyor.direction != s.direction) || s.buildings[s.player.x][s.player.y] == nil do s.buildings[s.player.x][s.player.y] = Conveyor{direction = s.direction}
    }
    if rl.IsKeyDown(rl.KeyboardKey.X) {
        if _, is_drill := s.buildings[s.player.x][s.player.y].(Drill); is_drill {
            s.buildings[s.player.x][s.player.y] = {}
            s.buildings[s.player.x+1][s.player.y] = {}
            s.buildings[s.player.x+1][s.player.y+1] = {}
            s.buildings[s.player.x][s.player.y+1] = {}
        }
        else do s.buildings[s.player.x][s.player.y] = {} 
    }
}

draw_border :: proc(x, y, w, h: int, bg_color: rl.Color = {}, fg_color: rl.Color = rl.WHITE, fill: bool = false) {
    if fill {
        dest := rl.Rectangle {
            x = f32(x) * s.char_width * s.scale,
            y = f32(y) * s.char_width * s.scale,
            width = f32(w) * s.char_width * s.scale,
            height = f32(h) * s.char_height * s.scale,
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
    for i := y+1; i < h + y - 1; i += 1 {
        yw := f32(i) * s.char_height * s.scale
        left_pos := rl.Vector2 { f32(x) * s.char_width * s.scale , yw }
        right_pos := rl.Vector2 { f32(w + x - 1) * s.char_width * s.scale, yw }
        draw_char('|', left_pos, s.scale, fg_color)
        draw_char('|', right_pos, s.scale, fg_color)
    }
}

check_boundaries :: proc(pos: [2]int) -> bool {
    return pos.x >= 0 && pos.x < WORLD_WIDTH && pos.y >= 0 && pos.y < WORLD_HEIGHT  
}

drill_ore_count :: proc(drill: Drill) -> int {
    count: int = 0
    for ore in drill.ores {
        count += ore.count
    }
    return count
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
    
    s.font_texture = rl.LoadTexture("./output.png")
    s.char_width = f32(int(s.font_texture.width) / ATLAS_COLS);
    s.char_height = f32(int(s.font_texture.height) / ATLAS_ROWS);
    
    s.grid_rows, s.grid_cols = grid_size()

    s.player.x = WORLD_WIDTH / 2
    s.player.y = WORLD_HEIGHT / 2
    
    for i in 0..<CLUSTER_COUNT {
        max_tile := i32(max(OreTile)) + 1
        tile := OreTile(rand.int31_max(max_tile))
        cluster_generation(tile)
    }
    
    offsets := OFFSETS
    opposite := OPPOSITE
    perpendiculars := PERPENDICULARS
    for !rl.WindowShouldClose() {
        rl.BeginDrawing()
        
        if rl.IsWindowResized() {
            s.window_width = rl.GetScreenWidth()
            s.window_height = rl.GetScreenHeight()

            s.grid_rows, s.grid_cols = grid_size()
        }
        
        rl.ClearBackground(BG_COLOR)
        dt := rl.GetFrameTime()
        
        input(dt)

        for i := 0; i < WORLD_WIDTH; i += 1 {
            for j := 0; j < WORLD_HEIGHT; j += 1 {
                switch &building in s.buildings[i][j] {
                    case nil:
                    case Drill: 
                        next_ore := s.world[i + building.next_tile % 2][j + building.next_tile / 2]
                        
                        if building.drilling_timer >= DRILLING_TIME {
                            if drill_ore_count(building) < building.capacity {
                                if next_ore != .None {
                                    if len(building.ores) != 0 && building.ores[len(building.ores)-1].type == next_ore {
                                        building.ores[len(building.ores)-1].count += 1
                                    } else {
                                        append(&building.ores, Ore{next_ore, 1})
                                    } 
                                } 
                                building.next_tile = (building.next_tile + 1) % 4
                            } 
                            building.drilling_timer = 0
                        }
                        building.drilling_timer += dt
                        
                        next_pos := [2][2]int{{i,j},{i,j}}
                        switch building.direction {
                            case .Right: 
                                next_pos[0] += 2 * offsets[building.direction] 
                                next_pos[1] += 2 * offsets[building.direction] + {0, 1} 
                            case .Left: 
                                next_pos[0] += offsets[building.direction] 
                                next_pos[1] += offsets[building.direction] + {0, 1} 
                            case .Down: 
                                next_pos[0] += 2 * offsets[building.direction] 
                                next_pos[1] += 2 * offsets[building.direction] + {1, 0} 
                            case .Up: 
                                next_pos[0] += offsets[building.direction] 
                                next_pos[1] += offsets[building.direction] + {1, 0} 
                        }
                        skip: for pos in next_pos {
                            world_pos := rl.Vector2 {f32(pos.x), f32(pos.y)} + 0.5
                            
                            if drill_ore_count(building) > 0 {
                                for item in s.items {
                                    if rl.Vector2Length(item.pos - world_pos) < 2 * ORE_SCALE {
                                        continue skip
                                    }  
                                }
                                building.ores[0].count -= 1
                                fmt.println(len(s.items))
                                
                                append(&s.items, Item{world_pos, building.ores[0].type}) 
                                if building.ores[0].count <= 0 do ordered_remove(&building.ores, 0) 
                            }
                        }
                    case Conveyor:
                    case Part:
                }
            }
        }
        for &item in s.items {
            cell_pos := [2]int{int(item.pos.x), int(item.pos.y)}

            conveyor, is_conveyor := s.buildings[cell_pos.x][cell_pos.y].(Conveyor)
            if is_conveyor {
                switch conveyor.direction {
                    case .Right:
                        item.pos += {1, f32(cell_pos.y)+0.5-item.pos.y} * dt * TRANSPORTATION_SPEED * {1, 3.5}
                    case .Left:
                        item.pos += {-1, f32(cell_pos.y)+0.5-item.pos.y} * dt * TRANSPORTATION_SPEED * {1, 3.5}
                    case .Down:
                        item.pos += {f32(cell_pos.x)+0.5-item.pos.x, 1} * dt * TRANSPORTATION_SPEED * {3.5, 1}
                    case .Up:
                        item.pos += {f32(cell_pos.x)+0.5-item.pos.x, -1} * dt * TRANSPORTATION_SPEED * {3.5, 1}
                }
            }
        }

        for &i_item in s.items {
            for j_item in s.items {
                if rl.Vector2Length(i_item.pos - j_item.pos) < 2 * ORE_SCALE {
                    l := rl.Vector2Length(i_item.pos - j_item.pos) - 2 * ORE_SCALE
                    i_item.pos -= rl.Vector2Normalize(i_item.pos - j_item.pos) * l
                }  
            }
        } 

        first_col := max(0, s.player.x - s.grid_cols/2) + 1
        last_col  := min(s.player.x + (s.grid_cols+1)/2 - 1, WORLD_WIDTH) 
        first_row := max(0, s.player.y - s.grid_rows/2) + 1
        last_row  := min(s.player.y + (s.grid_rows+1)/2 - 1, WORLD_HEIGHT)
        
        for i := first_col; i < last_col; i += 1 {
            for j := first_row; j < last_row; j += 1 {
                ch_ore: u8
                #partial switch s.world[i][j] {
                    case .None:     continue
                    case .Iron:     ch_ore = 'I'
                    case .Tungsten: ch_ore = 'T'
                    case .Coal:     ch_ore = 'C'
                    case: panic(fmt.aprintf("Unknown ore type: %v", s.world[i][j]))
                }
                
                pos := rl.Vector2 {
                    f32(i - s.player.x + s.grid_cols/2) * s.char_width * s.scale,
                    f32(j - s.player.y + s.grid_rows/2) * s.char_height * s.scale
                }

                draw_char(ch_ore, pos, s.scale)
            }
        }
        for i := first_col; i < last_col; i += 1 {
            for j := first_row; j < last_row; j += 1 {
                pos := rl.Vector2 {
                    f32(i - s.player.x + s.grid_cols/2) * s.char_width * s.scale,
                    f32(j - s.player.y + s.grid_rows/2) * s.char_height * s.scale
                }
                dest := rl.Rectangle {
                    x = pos.x,
                    y = pos.y,
                    width = s.char_width * s.scale,
                    height = s.char_height * s.scale,
                }

                
                switch building in s.buildings[i][j] {
                    case nil: 
                    case Conveyor: rl.DrawRectangleRec(dest, rl.DARKGRAY)
                    case Drill: 
                        dest := rl.Rectangle {
                            x = pos.x,
                            y = pos.y,
                            width = s.char_width * s.scale * 2,
                            height = s.char_height * s.scale * 2,
                        }
                        
                        rl.DrawRectangleRec(dest, BG_COLOR)
                    case Part:
                }
            }
        }
        for i := first_col; i < last_col; i += 1 {
            for j := first_row; j < last_row; j += 1 {
                pos := rl.Vector2 {
                    f32(i - s.player.x + s.grid_cols/2) * s.char_width * s.scale,
                    f32(j - s.player.y + s.grid_rows/2) * s.char_height * s.scale
                }
        
                switch building in s.buildings[i][j] {
                    case nil: 
                    case Conveyor:
                        switch building.direction {
                            case .Right: draw_char('>', pos, s.scale)
                            case .Left:  draw_char('<', pos, s.scale)
                            case .Down:  draw_char('~'+1, pos, s.scale)
                            case .Up:    draw_char('~'+2, pos, s.scale)
                        }
                    case Drill: 
                        draw_char('D', pos + 0.375*{s.char_width, s.char_height}*s.scale, 1.25 * s.scale, rl.MAGENTA)
                        switch building.direction {
                            case .Right: draw_char('>', pos + 0.5*{s.char_width * 2.2, s.char_height} * s.scale, s.scale)
                            case .Left:  draw_char('<', pos + 0.5*{s.char_width * -0.2, s.char_height} * s.scale, s.scale)
                            case .Down:  draw_char('~'+1, pos + 0.5*{s.char_width, s.char_height * 2.1} * s.scale, s.scale)
                            case .Up:    draw_char('~'+2, pos + 0.5*{s.char_width, s.char_height * -0.1} * s.scale, s.scale)
                        }
                        
                    case Part:
                }
            }
        }
        
        for item in s.items {
            i_pos := rl.Vector2{
                s.scale*s.char_width*(item.pos.x - f32(s.player.x) + f32(s.grid_cols/2) + 0.5 * ORE_SCALE - 0.5),
                s.scale*s.char_height*(item.pos.y - f32(s.player.y) + f32(s.grid_rows/2) + 0.5 * ORE_SCALE - 0.5),
            }
            switch item.ore {
                case .Iron: draw_char('I', i_pos, s.scale * ORE_SCALE, rl.GOLD)
                case .Tungsten: draw_char('T', i_pos, s.scale * ORE_SCALE, rl.GOLD)
                case .Coal: draw_char('C', i_pos, s.scale * ORE_SCALE, rl.GOLD)
                case .None: 
            }
            
            circle_pos := rl.Vector2{
                s.scale*s.char_width*(item.pos.x - f32(s.player.x) + f32(s.grid_cols/2)),
                s.scale*s.char_height*(item.pos.y - f32(s.player.y) + f32(s.grid_rows/2)),
            }            
            rl.DrawCircleLinesV(circle_pos, s.scale*ORE_SCALE*s.char_width, rl.RED)
        }

        
        // PLAYER
        player_pos := rl.Vector2 {
            f32(s.grid_cols/2) * s.char_width * s.scale,
            f32(s.grid_rows/2) * s.char_height * s.scale
        }
        rl.DrawRectangleV(player_pos, {s.char_width, s.char_height}*s.scale, BG_COLOR)
        draw_char('@', player_pos, s.scale, rl.VIOLET)
            
        // RAMKA he is right
        draw_border(0, 0, s.grid_cols, s.grid_rows, BG_COLOR)
        draw_border(s.grid_cols-3, 0, 3, 3, BG_COLOR, fill = true)
        switch s.direction {
            case .Right: draw_char('>',   {s.char_width*f32(s.grid_cols-2), s.char_height*1} * s.scale, s.scale, rl.SKYBLUE)
            case .Left:  draw_char('<',   {s.char_width*f32(s.grid_cols-2), s.char_height*1} * s.scale, s.scale, rl.SKYBLUE)
            case .Down:  draw_char('~'+1, {s.char_width*f32(s.grid_cols-2), s.char_height*1} * s.scale, s.scale, rl.SKYBLUE)
            case .Up:    draw_char('~'+2, {s.char_width*f32(s.grid_cols-2), s.char_height*1} * s.scale, s.scale, rl.SKYBLUE)
        }
        
        if s.grid_rows > STOOD_MENU_HEIGHT && s.grid_cols > STOOD_MENU_WIDTH && s.stood_menu {
            // Ore text
            text_ore := fmt.bprintf(s.text_buffer[:], "%v", s.world[s.player.x][s.player.y])

            // Building text
            text_building: string
            switch building in s.buildings[s.player.x][s.player.y] {
                case nil:      text_building = fmt.bprintf(s.text_buffer[len(text_ore):], "None")
                case Drill:    
                    if len(building.ores) == 0 {
                        text_building = fmt.bprintf(s.text_buffer[len(text_ore):], "Drill[%v:%v]", nil, nil)
                    } else {
                        text_building = fmt.bprintf(s.text_buffer[len(text_ore):], "Drill[%v:%v]", building.ores[0].type,building.ores[0].count)
                    }
                    
                case Part:     
                    drill := s.buildings[building.main_pos.x][building.main_pos.y].(Drill)
                    
                    if len(drill.ores) == 0 {
                        text_building = fmt.bprintf(s.text_buffer[len(text_ore):], "Drill[%v:%v]", nil, nil)
                    } else {
                        text_building = fmt.bprintf(s.text_buffer[len(text_ore):], "Drill[%v:%v]", drill.ores[0].type, drill.ores[0].count)
                    }
                case Conveyor: text_building = fmt.bprintf(s.text_buffer[len(text_ore):], "Conveyor_%v[%v]", building.direction, building.ore_type)
                case: panic(fmt.aprintf("Unknown building type %v", building))
            }

            border_w := max(len(text_building) + 2, STOOD_MENU_WIDTH)
            draw_border(0, 0, border_w, STOOD_MENU_HEIGHT, BG_COLOR, fill = true)
            draw_text("STOOD ON:",   {s.char_width, s.char_height*1} * s.scale, s.scale)
            draw_text(text_ore,      {s.char_width, s.char_height*2} * s.scale, s.scale)
            draw_text(text_building, {s.char_width, s.char_height*3} * s.scale, s.scale)
        }
        
        rl.DrawFPS(14, 14)
        rl.EndDrawing()
    }    
}
    
