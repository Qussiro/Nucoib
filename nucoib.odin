package nucoib

import "core:fmt"
import "core:strings"
import "core:math"
import "core:math/rand"
import rl "vendor:raylib"
import "core:container/queue"
import "core:slice"
import "base:runtime"

COLS            :: 18
ROWS            :: 7
STOOD_MENU_H    :: 5
STOOD_MENU_W    :: 17
WORLD_WIDTH     :: 1000
WORLD_HEIGHT    :: 1000
CLUSTER_SIZE    :: 100
CLUSTER_COUNT   :: 10000
MIN_SCALE       :: f32(1)
MAX_SCALE       :: f32(20)
ZOOM_COOLDOWN   :: f32(0.0)
MOVE_COOLDOWN   :: f32(0.05)
DRILLING_TIME      :: f32(2) 


World :: [WORLD_WIDTH][WORLD_HEIGHT]OreTile
Buildings :: [WORLD_WIDTH][WORLD_HEIGHT]BuildingTile


Player :: struct { 
    x : i32,
    y : i32,
}

Drill :: struct {
    ore_type: OreTile,
    ore_count: i32,
    drilling_timer: f32,
    capacity: i32,
}

Conveyor :: struct {
    direction: Direction
}

BuildingTile :: union {
    Drill,
    Conveyor,
}

OreTile :: enum (u8) {
    NONE,
    IRON,
    TUNGSTEN,
    COAL,
}

Direction :: enum {
   RIGHT,
   DOWN,
   LEFT,
   UP, 
}

window_width := i32(1280)
window_height := i32(720)
world: ^World
buildings: ^Buildings
player: Player
char_width: i32
char_height: i32
font_texture: rl.Texture2D
count_clusters_sizes: [CLUSTER_SIZE + 1]i32
scale := f32(2)
rows: i32
cols: i32
pressed_move: f32
pressed_zoom: f32
direction := Direction.RIGHT
text_buffer: [512]u8
stood_menu: bool

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
    for i := 0; i < len(text); i+=1 {
        char_pos := rl.Vector2 {
            f32(i32(i) * char_width) * scale + pos.x,
            pos.y,
        }
        draw_char(text[i], char_pos, scale)
    }
}

draw_char :: proc(c: u8, pos: rl.Vector2, scale: f32, rotation: f32 = 0) {
    source := rl.Rectangle {
        x = f32(i32(c - 32) % COLS * char_width),
        y = f32(i32(c - 32) / COLS * char_height),
        width = f32(char_width),
        height = f32(char_height),
    }
    dest := rl.Rectangle {
        x = pos.x + f32(char_width)/2 * scale,
        y = pos.y + f32(char_height)/2 * scale,
        width = f32(char_width) * scale,
        height = f32(char_height) * scale,
    }
    origin := rl.Vector2 {f32(char_width), f32(char_height)}/2 * scale
    
    rl.DrawTexturePro(font_texture, source, dest, origin, rotation, rl.WHITE) 
}

grid_size :: proc() -> (i32, i32) {
    rows := i32(f32(window_height) / (f32(char_height) * scale))
    cols := i32(f32(window_width) / (f32(char_width) * scale))
    return rows, cols
}

input :: proc(dt : f32) {
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
            rows, cols = grid_size()
        }
        if rl.IsKeyPressed(rl.KeyboardKey.EQUAL) {
            scale = min(scale*1.1, MAX_SCALE)
            rows, cols = grid_size()
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
        fmt.println("Stood_menu:",stood_menu)
    }
    if rl.IsKeyDown(rl.KeyboardKey.C) {
        buildings[player.x][player.y] = Conveyor{direction}
    }
    if rl.IsKeyDown(rl.KeyboardKey.LEFT_SHIFT) && rl.IsKeyDown(rl.KeyboardKey.D){
        buildings[player.x][player.y] = BuildingTile{}
    }
}

draw_border :: proc(x, y, w, h: i32, fill: bool = false) {
    for i := i32(0); i < w; i += 1 {
        x := f32(i * char_width) * scale
        upper_pos := rl.Vector2 { x, 0 }
        lower_pos := rl.Vector2 { x, f32((h - 1) * char_height) * scale }
        if (i == 0 || i == w - 1) {
            draw_char('+', upper_pos, scale)
            draw_char('+', lower_pos, scale)
        } else {
            draw_char('-', upper_pos, scale)
            draw_char('-', lower_pos, scale)
        }
    }
    for i := i32(1); i < h - 1; i += 1 {
        y := f32(i * char_height) * scale
        left_pos := rl.Vector2 { 0, y }
        right_pos := rl.Vector2 { f32((w - 1) * char_width) * scale, y }
        draw_char('|', left_pos, scale)
        draw_char('|', right_pos, scale)
    }
    if fill {
        for i := i32(1); i < w - 1; i += 1 {
            for j := i32(1); j < h - 1; j += 1 {
                char_pos := rl.Vector2 {
                    f32(i * char_width) * scale,
                    f32(j * char_height) * scale
                }
                draw_char(' ', char_pos, scale)
            } 
        }
    }
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
    
    fmt.println("Map size: ", 2*size_of(World), "Bytes")
    
    font_texture = rl.LoadTexture("./charmap-oldschool_white12.png")
    char_width = font_texture.width / COLS;
    char_height = font_texture.height / ROWS;
    
    rows, cols = grid_size()

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
    
    for !rl.WindowShouldClose() {
        rl.BeginDrawing()
        
        if rl.IsWindowResized() {
            window_width = rl.GetScreenWidth()
            window_height = rl.GetScreenHeight()

            rows, cols = grid_size()
        }
        
        rl.ClearBackground(rl.GetColor(0x202020FF))
        dt := rl.GetFrameTime()
        
        input(dt)

        for i := 0; i < WORLD_WIDTH; i += 1 {
            for j := 0; j < WORLD_HEIGHT; j += 1 {
                switch &building in buildings[i][j]{
                    case Drill: 
                        if world[i][j] == .NONE do continue

                        assert(building.ore_type == world[i][j] || building.ore_type == .NONE, "Smth wrong with ur ORES!!! FIX IT!")
                        building.ore_type = world[i][j]
                        if building.drilling_timer >= DRILLING_TIME {
                            if building.ore_count < building.capacity do building.ore_count += 1
                            building.drilling_timer = 0
                        }
                        building.drilling_timer += dt
                    case Conveyor:
                    case nil:
                }
            }
        }

        first_col := max(0, player.x - cols/2)
        last_col  := min(player.x + cols/2, WORLD_WIDTH)
        first_row := max(0, player.y - rows/2)
        last_row  := min(player.y + rows/2, WORLD_HEIGHT)
        
        for i := first_col; i < last_col; i += 1 {
            for j := first_row; j < last_row; j += 1 {
                ch_ore: u8
                ch_building: u8
                #partial switch world[i][j] {
                    case .NONE:     ch_ore = ' '
                    case .IRON:     ch_ore = 'I'
                    case .TUNGSTEN: ch_ore = 'T'
                    case .COAL:     ch_ore = 'C'
                    case: unimplemented("BRUH!")
                }
                switch _ in buildings[i][j] {
                    case nil:      ch_building = ' '
                    case Drill:     ch_building = 'D'
                    case Conveyor:  ch_building = '>'
                }
                
                pos := rl.Vector2 {
                    f32((i - player.x + cols/2) * char_width) * scale,
                    f32((j - player.y + rows/2) * char_height) * scale
                }

                draw_char(ch_ore, pos, scale)
                
                switch building in buildings[i][j] {
                    case Conveyor:
                        switch building.direction{
                            case .RIGHT: draw_char(ch_building, pos, scale, 0)
                            case .DOWN: draw_char(ch_building, pos, scale, 90)
                            case .LEFT: draw_char(ch_building, pos, scale, 180)
                            case .UP: draw_char(ch_building, pos, scale, 270)
                        }
                    case nil: 
                    case Drill: draw_char(ch_building, pos, scale, 0)
                }
            }
        }

        // PLAYER
        player_pos := rl.Vector2 {
            f32(cols/2 * char_width) * scale,
            f32(rows/2 * char_height) * scale
        }
        draw_char('@', player_pos, scale)

        // RAMKA he is right
        draw_border(0, 0, cols, rows)
        
        if rows > STOOD_MENU_H && cols > STOOD_MENU_W && stood_menu {
        
            // Ore text
            text_ore := fmt.bprintf(text_buffer[:], "%v", world[player.x][player.y])

            text_building: string
            // Building text
            switch building in buildings[player.x][player.y] {
                case Drill: text_building = fmt.bprintf(text_buffer[len(text_ore):], "DRILL[%v:%v]", building.ore_type, building.ore_count)
                case Conveyor: text_building = fmt.bprintf(text_buffer[len(text_ore):], "CONVEYOR_%v", building.direction)
                case nil: text_building = fmt.bprintf(text_buffer[len(text_ore):], "NONE")
                case: fmt.println(building)
            }
            border_w := max(i32(len(text_building)+2), STOOD_MENU_W)
            draw_border(0, 0, border_w, STOOD_MENU_H, true)
            draw_text("STOOD ON:", {f32(char_width), f32(char_height)} * scale, scale)
            draw_text(text_ore, {f32(char_width), f32(char_height)*2} * scale, scale)
            draw_text(text_building, {f32(char_width), f32(char_height)*3} * scale, scale)
        }
        
        rl.DrawFPS(14, 14)
        rl.EndDrawing()
    }    
}
