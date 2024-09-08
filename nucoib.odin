package nucoib

import "core:fmt"
import "core:strings"
import "core:math"
import "core:math/rand"
import rl "vendor:raylib"
import "core:container/queue"
import "core:slice"
import "base:runtime"

COLS          :: 18
ROWS          :: 7
WINDOW_WIDTH  :: 1280
WINDOW_HEIGHT :: 720
WORLD_WIDTH   :: 1000
WORLD_HEIGHT  :: 1000
CLUSTER_SIZE  :: 100
CLUSTER_COUNT :: 1000
MIN_SCALE     :: f32(1)
MAX_SCALE     :: f32(20)

World :: [WORLD_WIDTH][WORLD_HEIGHT]Tile

Player :: struct { 
    x : i32,
    y : i32,
}

Tile :: enum (u8) {
    NONE,
    IRON,
    TUNGSTEN,
    COAL,
}

world: ^World
player: Player
char_width: i32
char_height: i32
font_texture: rl.Texture2D
count_clusters_sizes: [CLUSTER_SIZE + 1]i32
scale := f32(2)

cluster_generation :: proc(tile: Tile) {
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
        
        if(ci.x - 1 != -1) {
            queue.push_back(&tovisit, Point{ci.x-1, ci.y})
        }
        if(ci.x + 1 != WORLD_WIDTH) {
            queue.push_back(&tovisit, Point{ci.x+1, ci.y})
        }
        if(ci.y - 1 != -1) {
            queue.push_back(&tovisit, Point{ci.x, ci.y-1})
        }
        if(ci.y + 1 != WORLD_HEIGHT) {
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

draw_char :: proc(c: u8, pos: rl.Vector2, scale: f32) {
    source := rl.Rectangle {
        x = f32(i32(c - 32) % COLS * char_width),
        y = f32(i32(c - 32) / COLS * char_height),
        width = f32(char_width),
        height = f32(char_height),
    }
    dest : rl.Rectangle = {
        x = pos.x,
        y = pos.y,
        width = f32(char_width) * scale,
        height = f32(char_height) * scale,
    }
    rl.DrawTexturePro(font_texture, source, dest, {}, 0, rl.WHITE) 
}

grid_size :: proc() -> (i32, i32) {
    rows := i32(f32(WINDOW_HEIGHT) / (f32(char_height) * scale))
    cols := i32(f32(WINDOW_WIDTH) / (f32(char_width) * scale))
    return rows, cols
}

main :: proc() {
    rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "nucoib")
    rl.SetTargetFPS(60)
    
    err: runtime.Allocator_Error
    world, err = new(World)
    if(err != nil) {
        fmt.println("Buy MORE RAM! --> ", err)
        fmt.println("Need memory: ", size_of(World), "Bytes")
    }
    fmt.println("Map size: ", size_of(World), "Bytes")
    
    font_texture = rl.LoadTexture("./charmap-oldschool_white.png")
    char_width = font_texture.width / COLS;
    char_height = font_texture.height / ROWS;
    
    rows, cols := grid_size()

    player.x = WORLD_WIDTH / 2
    player.y = WORLD_HEIGHT / 2
    
    for i in 0..<CLUSTER_COUNT {
        max_tile := i32(max(Tile)) + 1
        tile := Tile(rand.int31_max(max_tile))
        cluster_generation(tile)
    }
    for v,i in count_clusters_sizes {
        fmt.println(i, ":", v)
    }
    
    for !rl.WindowShouldClose() {
        rl.BeginDrawing()
        rl.ClearBackground(rl.GetColor(0x202020FF))
        
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
        if rl.IsKeyDown(rl.KeyboardKey.MINUS) {
            scale = max(MIN_SCALE, scale*0.9)
            rows, cols = grid_size()
        }
        if rl.IsKeyDown(rl.KeyboardKey.EQUAL) {
            scale = min(scale*1.1, MAX_SCALE)
            rows, cols = grid_size()
        }

        first_col := max(0, player.x - cols/2)
        last_col  := min(player.x + cols/2, WORLD_WIDTH)
        first_row := max(0, player.y - rows/2)
        last_row  := min(player.y + rows/2, WORLD_HEIGHT)
        
        for i := first_col; i < last_col; i += 1 {
            for j := first_row; j < last_row; j += 1 {
                ch: u8
                #partial switch world[i][j] {
                    case .NONE:     ch = ' '
                    case .IRON:     ch = 'I'
                    case .TUNGSTEN: ch = 'T'
                    case .COAL:     ch = 'C'
                    case: unimplemented("BRUH!")
                }
                pos := rl.Vector2 {
                    f32((i - player.x + cols/2) * char_width) * scale,
                    f32((j - player.y + rows/2) * char_height) * scale
                }
                draw_char(ch, pos, scale)
            }
        }

        // PLAYER
        player_pos := rl.Vector2 {
            f32(cols/2 * char_width) * scale,
            f32(rows/2 * char_height) * scale
        }
        draw_char('@', player_pos, scale)

        // SETKA net RAMKA
        for i := i32(0); i < cols; i += 1 {
            x := f32(i * char_width) * scale
            upper_pos := rl.Vector2 { x, 0 }
            lower_pos := rl.Vector2 { x, f32((rows - 1) * char_height) * scale }
            if (i == 0 || i == cols - 1) {
                draw_char('+', upper_pos, scale)
                draw_char('+', lower_pos, scale)
            } else {
                draw_char('-', upper_pos, scale)
                draw_char('-', lower_pos, scale)
            }
        }
        for i := i32(1); i < rows - 1; i += 1 {
            y := f32(i * char_height) * scale
            left_pos := rl.Vector2 { 0, y }
            right_pos := rl.Vector2 { f32((cols - 1) * char_width) * scale, y }
            draw_char('|', left_pos, scale)
            draw_char('|', right_pos, scale)
        }
        
        rl.DrawFPS(14, 14)
        rl.EndDrawing()
    }    
}
