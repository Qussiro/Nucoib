package nucoib

import "core:fmt"
import "core:strings"
import "core:math"
import "core:math/rand"
import "core:container/queue"
import "core:slice"
import "base:runtime"
import rl "vendor:raylib"
import gl "vendor:OpenGL"
import glfwb "vendor:glfw/bindings"
import glfw "vendor:glfw"

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
DRILLING_TIME        :: f32(2) 
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
    ore_type:       OreTile,
    ore_count:      int,
    capacity:       int,
    drilling_timer: f32,
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

world:                ^World
buildings:            ^Buildings
player:               Player
font_texture:         rl.Texture2D
char_width:           f32
char_height:          f32
grid_rows:            int
grid_cols:            int
pressed_move:         f32
pressed_zoom:         f32
stood_menu:           bool
count_clusters_sizes: [CLUSTER_SIZE + 1]int
text_buffer:          [512]u8

window_width  := i32(1280)
window_height := i32(720)
scale         := f32(2)
direction     := Direction.Right

vertices := [?]f32 {
    -0.5, -0.5, 0.0,
     0.5, -0.5, 0.0,
     0.0,  0.5, 0.0
};
  
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
        world[ci.x][ci.y] = tile
        count_usefull += 1
    }
    
    count_clusters_sizes[count_usefull] += 1
    delete(visited)
    queue.destroy(&tovisit)
}

draw_text :: proc(text: string, pos: rl.Vector2, scale: f32) {
    for i := 0; i < len(text); i += 1 {
        char_pos := rl.Vector2 {
            f32(i) * char_width * scale + pos.x,
            pos.y,
        }
        draw_char(text[i], char_pos, scale)
    }
}

draw_char :: proc(c: u8, pos: rl.Vector2, scale: f32, bg_color: rl.Color = {}, fg_color: rl.Color = rl.WHITE, rotation: f32 = 0) {
    source := rl.Rectangle {
        x = f32(int(c - 32) % ATLAS_COLS) * char_width,
        y = f32(int(c - 32) / ATLAS_COLS) * char_height,
        width = char_width,
        height = char_height,
    }
    dest := rl.Rectangle {
        x = pos.x + char_width/2 * scale,
        y = pos.y + char_height/2 * scale,
        width = char_width * scale,
        height = char_height * scale,
    }
    origin := rl.Vector2 {char_width, char_height} / 2 * scale

    rl.DrawRectanglePro(dest, origin, rotation, bg_color)
    rl.DrawTexturePro(font_texture, source, dest, origin, rotation, fg_color) 
}

grid_size :: proc() -> (int, int) {
    grid_rows := int(f32(window_height) / (char_height * scale))
    grid_cols := int(f32(window_width) / (char_width * scale))
    return grid_rows, grid_cols
}

input :: proc(dt: f32) {
    if pressed_move > 0 do pressed_move -= dt
    else {
        if rl.IsKeyDown(rl.KeyboardKey.UP) && player.y > 0 {
            player.y -= 1
        }
        if rl.IsKeyDown(rl.KeyboardKey.RIGHT) && player.x < WORLD_WIDTH - 1 {
            player.x += 1
        }
        if rl.IsKeyDown(rl.KeyboardKey.LEFT) && player.x > 0 {
            player.x -= 1 
        }
        if rl.IsKeyDown(rl.KeyboardKey.DOWN) && player.y < WORLD_HEIGHT - 1 {
            player.y += 1
        }  
        pressed_move = MOVE_COOLDOWN      
    }
    
    if pressed_zoom > 0 do pressed_zoom -= dt
    else {
        if rl.IsKeyPressed(rl.KeyboardKey.MINUS) {
            scale = max(MIN_SCALE, scale*0.9)
            grid_rows, grid_cols = grid_size()
        }
        if rl.IsKeyPressed(rl.KeyboardKey.EQUAL) {
            scale = min(scale*1.1, MAX_SCALE)
            grid_rows, grid_cols = grid_size()
        }
        pressed_zoom = ZOOM_COOLDOWN
    }
    
    if rl.IsKeyDown(rl.KeyboardKey.D) {
        buildings[player.x][player.y] = Drill{capacity = 10}
    }
    if rl.IsKeyPressed(rl.KeyboardKey.R) {
        direction = Direction((i32(direction) + 1) % (i32(max(Direction)) + 1))
        fmt.println(direction)
    }
    if rl.IsKeyPressed(rl.KeyboardKey.GRAVE) {
        stood_menu = !stood_menu
        fmt.println("Stood_menu:", stood_menu)
    }
    if rl.IsKeyDown(rl.KeyboardKey.C) {
        buildings[player.x][player.y] = Conveyor{direction = direction}
    }
    if rl.IsKeyDown(rl.KeyboardKey.LEFT_SHIFT) && rl.IsKeyDown(rl.KeyboardKey.D) {
        buildings[player.x][player.y] = {}
    }
}

draw_border :: proc(x, y, w, h: int, bg_color: rl.Color = {}, fg_color: rl.Color = rl.WHITE, fill: bool = false) {
    for i := 0; i < w; i += 1 {
        x := f32(i) * char_width * scale
        upper_pos := rl.Vector2 { x, 0 }
        lower_pos := rl.Vector2 { x, f32(h - 1) * char_height * scale }
        if (i == 0 || i == w - 1) {
            draw_char('+', upper_pos, scale, bg_color, fg_color)
            draw_char('+', lower_pos, scale, bg_color, fg_color)
        } else {
            draw_char('-', upper_pos, scale, bg_color, fg_color)
            draw_char('-', lower_pos, scale, bg_color, fg_color)
        }
    }
    for i := 1; i < h - 1; i += 1 {
        y := f32(i) * char_height * scale
        left_pos := rl.Vector2 { 0, y }
        right_pos := rl.Vector2 { f32(w - 1) * char_width * scale, y }
        draw_char('|', left_pos, scale, bg_color, fg_color)
        draw_char('|', right_pos, scale, bg_color, fg_color)
    }
    if fill {
        for i := 1; i < w - 1; i += 1 {
            for j := 1; j < h - 1; j += 1 {
                char_pos := rl.Vector2 {
                    f32(i) * char_width * scale,
                    f32(j) * char_height * scale
                }
                draw_char(' ', char_pos, scale, bg_color, fg_color)
            } 
        }
    }
}

check_boundaries :: proc(pos: [2]int) -> bool {
    return pos.x >= 0 && pos.x < WORLD_WIDTH && pos.y >= 0 && pos.y < WORLD_HEIGHT  
}

main :: proc() {
    rl.InitWindow(window_width, window_height, "nucoib")
    rl.SetWindowState({.WINDOW_RESIZABLE})
    rl.SetTargetFPS(60)
    
    err: runtime.Allocator_Error
    world, err = new(World)
    if err != nil {
        fmt.println("Buy MORE RAM! --> ", err)
        fmt.println("Need memory: ", size_of(World), "Bytes")
    }
    buildings, err = new(Buildings)
    if err != nil {
        fmt.println("Buy MORE RAM! --> ", err)
        fmt.println("Need memory: ", size_of(Buildings), "Bytes")
    }
    
    fmt.println("Map size: ", size_of(World) + size_of(Buildings), "Bytes")
    
    // font_texture = rl.LoadTexture("./charmap-oldschool_white12.png")
    font_texture = rl.LoadTexture("./output.png")
    char_width = f32(int(font_texture.width) / ATLAS_COLS);
    char_height = f32(int(font_texture.height) / ATLAS_ROWS);
    
    grid_rows, grid_cols = grid_size()

    player.x = WORLD_WIDTH / 2
    player.y = WORLD_HEIGHT / 2
    
    for i in 0..<CLUSTER_COUNT {
        max_tile := i32(max(OreTile)) + 1
        tile := OreTile(rand.int31_max(max_tile))
        cluster_generation(tile)
    }
    // for v,i in count_clusters_sizes {
    //     fmt.println(i, ":", v)
    // }
    
    offsets := OFFSETS
    opposite := OPPOSITE
    perpendiculars := PERPENDICULARS

    avg_update_time: f64
    avg_render_time: f64
    time_count: int 

    gl.load_up_to(3,3,glfw.gl_set_proc_address)
    VAO: u32
    gl.GenVertexArrays(1, &VAO)  
    gl.BindVertexArray(VAO)
    VBO: u32
    gl.GenBuffers(1,&VBO)
    gl.BindBuffer(gl.ARRAY_BUFFER, VBO)  
    gl.BufferData(gl.ARRAY_BUFFER, len(vertices)*size_of(vertices[0]), &vertices[0], gl.STATIC_DRAW)
    shader := rl.LoadShader("./shader.vert", "./shader.frag")
    gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, 3 * size_of(f32), uintptr(0))
    gl.EnableVertexAttribArray(0)

    
    for !rl.WindowShouldClose() {
        rl.BeginDrawing()

        
                
        time_time := rl.GetTime()
        time_count += 1 
        
        if rl.IsWindowResized() {
            window_width = rl.GetScreenWidth()
            window_height = rl.GetScreenHeight()

            grid_rows, grid_cols = grid_size()
        }
        
        rl.ClearBackground(BG_COLOR)
        dt := rl.GetFrameTime()
        
        input(dt)
        
        for i := 0; i < WORLD_WIDTH; i += 1 {
            for j := 0; j < WORLD_HEIGHT; j += 1 {
                switch &building in buildings[i][j] {
                    case nil:
                    case Drill: 
                        if world[i][j] == .None do continue

                        assert(building.ore_type == world[i][j] || building.ore_type == .None, "Smth wrong with ur ORES!!! FIX IT!")
                        building.ore_type = world[i][j]
                        if building.drilling_timer >= DRILLING_TIME {
                            if building.ore_count < building.capacity do building.ore_count += 1
                            building.drilling_timer = 0
                        }
                        building.drilling_timer += dt

                        for direction in Direction{
                            next_pos := [2]int{i, j} + offsets[direction]
                        
                            if check_boundaries(next_pos) {
                                conveyor, is_conveyor := &buildings[next_pos.x][next_pos.y].(Conveyor)
                                if is_conveyor && conveyor.ore_type == .None && building.ore_count > 0 {
                                    if conveyor.direction in perpendiculars[direction] do conveyor.transportation_progress = 0.7
                                    building.ore_count -= 1
                                    conveyor.ore_type = building.ore_type
                                }
                            }
                        }
                    case Conveyor:
                        if building.ore_type == .None do continue
                        
                        building.transportation_progress += dt * TRANSPORTATION_SPEED
                        next_pos := [2]int{i, j} + offsets[building.direction]
                        max_progress: f32 = 1
                        
                        if check_boundaries(next_pos) { 
                            conveyor, is_conveyor := &buildings[next_pos.x][next_pos.y].(Conveyor)
                            if is_conveyor && conveyor.ore_type == .None && conveyor.direction != opposite[building.direction] {
                                match_perpendicular := conveyor.direction in perpendiculars[building.direction] 
                                
                                if match_perpendicular do max_progress = 1.7
                                
                                if building.transportation_progress >= max_progress {
                                    conveyor.ore_type = building.ore_type
                                    building.ore_type = .None
                                    building.transportation_progress = 0
                                
                                    if match_perpendicular do conveyor.transportation_progress = 0.7
                                }
                            }
                        }
                        building.transportation_progress = min(building.transportation_progress, max_progress)
                }
            }
        }

        avg_update_time += rl.GetTime() - time_time
        time_time = rl.GetTime()
        
        first_col := max(0, player.x - grid_cols/2)
        last_col  := min(player.x + grid_cols/2, WORLD_WIDTH)
        first_row := max(0, player.y - grid_rows/2)
        last_row  := min(player.y + grid_rows/2, WORLD_HEIGHT)
        
        for i := first_col; i < last_col; i += 1 {
            for j := first_row; j < last_row; j += 1 {
                ch_ore: u8
                #partial switch world[i][j] {
                    case .None:     ch_ore = ' '
                    case .Iron:     ch_ore = 'I'
                    case .Tungsten: ch_ore = 'T'
                    case .Coal:     ch_ore = 'C'
                    case: panic(fmt.aprintf("Unknown ore type: %v", world[i][j]))
                }
                
                pos := rl.Vector2 {
                    f32(i - player.x + grid_cols/2) * char_width * scale,
                    f32(j - player.y + grid_rows/2) * char_height * scale
                }

                draw_char(ch_ore, pos, scale)
                
                switch building in buildings[i][j] {
                    case nil: 
                    case Conveyor:
                        switch building.direction {
                            case .Right: draw_char('>', pos, scale, rl.DARKGRAY)
                            case .Left:  draw_char('<', pos, scale, rl.DARKGRAY)
                            case .Down:  draw_char('~'+1, pos, scale, rl.DARKGRAY)
                            case .Up:    draw_char('~'+2, pos, scale, rl.DARKGRAY)
                        }
                    case Drill: draw_char('D', pos, scale, BG_COLOR, fg_color = rl.MAGENTA)
                }
            }
        }
        
        for i := first_col; i < last_col; i += 1 {
            for j := first_row; j < last_row; j += 1 {
                conveyor, is_conveyor := &buildings[i][j].(Conveyor)
                if is_conveyor && conveyor.ore_type != .None {
                    pos := rl.Vector2 {
                        f32(i - player.x + grid_cols/2) * char_width * scale,
                        f32(j - player.y + grid_rows/2) * char_height * scale
                    }
                    
                    ore_offset: rl.Vector2

                    // MAGIC STUFF, DON`T TOUCH
                    switch conveyor.direction {
                        case .Right:
                            ore_offset =  {
                                char_width * scale * (conveyor.transportation_progress - ORE_SCALE), 
                                char_height * scale * (0.5 - 0.5*ORE_SCALE)
                            }
                        case .Down:
                            ore_offset =  {
                                char_width * scale * (0.5 - 0.5*ORE_SCALE),
                                char_height * scale * (conveyor.transportation_progress - ORE_SCALE)
                            } 
                        case .Left: 
                            ore_offset = rl.Vector2 {
                                char_width * scale * (1 - conveyor.transportation_progress), 
                                char_height * scale * (0.5 - 0.5*ORE_SCALE)
                            }
                        case .Up:
                            ore_offset =  {
                                char_width * scale * (0.5 - 0.5*ORE_SCALE),
                                char_height * scale * (1 - conveyor.transportation_progress) 
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
    
                    draw_char(c, ore_offset, scale * ORE_SCALE, fg_color = rl.GOLD)
                }
            }
        }

        // PLAYER
        player_pos := rl.Vector2 {
            f32(grid_cols/2) * char_width * scale,
            f32(grid_rows/2) * char_height * scale
        }
        draw_char('@', player_pos, scale, BG_COLOR)

        // RAMKA he is right
        draw_border(0, 0, grid_cols, grid_rows, BG_COLOR)
        
        if grid_rows > STOOD_MENU_HEIGHT && grid_cols > STOOD_MENU_WIDTH && stood_menu {
            // Ore text
            text_ore := fmt.bprintf(text_buffer[:], "%v", world[player.x][player.y])

            // Building text
            text_building: string
            switch building in buildings[player.x][player.y] {
                case nil:      text_building = fmt.bprintf(text_buffer[len(text_ore):], "None")
                case Drill:    text_building = fmt.bprintf(text_buffer[len(text_ore):], "DRILL[%v:%v]", building.ore_type, building.ore_count)
                case Conveyor: text_building = fmt.bprintf(text_buffer[len(text_ore):], "CONVEYOR_%v[%v]", building.direction, building.ore_type)
                case: panic(fmt.aprintf("Unknown building type %v", building))
            }

            border_w := max(len(text_building) + 2, STOOD_MENU_WIDTH)
            draw_border(0, 0, border_w, STOOD_MENU_HEIGHT, BG_COLOR, fill = true)
            draw_text("STOOD ON:",   {char_width, char_height * 1} * scale, scale)
            draw_text(text_ore,      {char_width, char_height * 2} * scale, scale)
            draw_text(text_building, {char_width, char_height * 3} * scale, scale)
        }
        
        avg_render_time += rl.GetTime() - time_time
        
        gl.UseProgram(shader.id)
        gl.BindVertexArray(VAO)
        gl.DrawArrays(gl.TRIANGLES, 0, 3)
        rl.DrawFPS(14, 14)
        rl.EndDrawing()
    }   

    avg_update_time = avg_update_time / f64(time_count)
    avg_render_time = avg_render_time / f64(time_count)
    fmt.println("avg_update_time: ", avg_update_time)
    fmt.println("avg_render_time: ", avg_render_time)
}
