package nucoib

import "core:fmt"
import "core:strings"
import "core:math"
import "core:math/rand"
import rl "vendor:raylib"
import "core:container/queue"
import "core:slice"
import "base:runtime"

COLS : i32 : 18
ROWS : i32 : 7
WINDOW_WIDTH : i32 : 1280
WINDOW_HEIGHT : i32 : 720
scale : f32 = 2 
WORLD_WIDTH : i32 : 230000
WORLD_HEIGHT : i32 : 230000
CLUSTER_SIZE :: 100
CLUSTER_COUNT :: 10000

Player :: struct { 
    x : i32,
    y : i32,
}

Tile :: enum (u8){
    NONE,
    IRON,
    TUNGSTEN,
    COAL,
}

world : ^[WORLD_WIDTH][WORLD_HEIGHT]Tile 
err : runtime.Allocator_Error

char_width : i32 
char_height : i32
font_texture : rl.Texture2D
count_useless : i32 = 0
count_clusters_sizes : [CLUSTER_SIZE + 1]i32 

cluster_generation :: proc(tile : Tile) {
    count_useless = 0
    cx := rand.int31_max(WORLD_WIDTH)
    cy := rand.int31_max(WORLD_HEIGHT)

    tovisit : queue.Queue([2]i32) 

    queue.push_back(&tovisit, [2]i32{cx, cy})
    visited : [dynamic][2]i32
    for queue.len(tovisit) > 0 {
        ci := queue.pop_front(&tovisit)
         
        if slice.contains(visited[:], ci) do continue
        append(&visited, ci)
        // y = -x/10+1
        if rand.float32() >= f32(-count_useless)/CLUSTER_SIZE+1 do continue

        // y = -log(x/10)
        // if rand.float32() >= -math.log10(f32(count_useless)/CLUSTER_SIZE) do continue      
        
        if(ci.x - 1 != -1) {
            queue.push_back(&tovisit, [2]i32{ci.x-1, ci.y})
        }
        if(ci.x + 1 != WORLD_WIDTH) {
            queue.push_back(&tovisit, [2]i32{ci.x+1, ci.y})
        }
        if(ci.y - 1 != -1) {
            queue.push_back(&tovisit, [2]i32{ci.x, ci.y-1})
        }
        if(ci.y + 1 != WORLD_HEIGHT) {
            queue.push_back(&tovisit, [2]i32{ci.x, ci.y+1})
        }
        world[ci.x][ci.y] = tile
        count_useless += 1
    }
    count_clusters_sizes[count_useless] += 1
    delete(visited)
    queue.destroy(&tovisit)
}

draw_text :: proc(text: string, pos: rl.Vector2, scale: f32) {
    for i := 0; i < len(text); i+=1 {
        char_pos : rl.Vector2 = {
            cast(f32) (cast (i32) i * char_width) * scale + pos.x,
            pos.y,
        }
        c : u8 = text[i] 
        draw_char(c, char_pos, scale)
    }
}

draw_char :: proc(c: u8, pos: rl.Vector2, scale: f32) {
    source : rl.Rectangle = {
        x = cast(f32) (cast(i32) (c - 32) % COLS * char_width),
        y = cast(f32) (cast(i32) (c - 32) / COLS * char_height),
        width = cast(f32) char_width,
        height = cast(f32) char_height,
    }
    dest : rl.Rectangle = {
        x = pos.x,
        y = pos.y,
        width = cast(f32) char_width * scale,
        height = cast(f32) char_height * scale,
    }
    rl.DrawTexturePro(font_texture, source, dest, {}, 0, rl.WHITE) 
}

player : Player
 

main :: proc() {
    rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "nucoib")
    rl.SetTargetFPS(60)
    
    world, err = new([WORLD_WIDTH][WORLD_HEIGHT]Tile)    
    if(world == nil) do fmt.println("Buy MORE RAM! --> ", err, "\n Need memory: ", size_of([WORLD_WIDTH][WORLD_HEIGHT]Tile), "Byte")
    fmt.println("Map size: ", size_of([WORLD_WIDTH][WORLD_HEIGHT]Tile), "Byte")
    
    // font : rl.Font = rl.LoadFont("./Riglos.ttf")
    font_texture = rl.LoadTexture("./charmap-oldschool_white.png")
    char_width = font_texture.width / COLS;
    char_height = font_texture.height / ROWS;
    
    rows : i32 = i32(f32(WINDOW_HEIGHT) / (f32(char_height) * scale))
    cols : i32 = i32(f32(WINDOW_WIDTH) / (f32(char_width) * scale))

    player.x = WORLD_WIDTH / 2
    player.y = WORLD_HEIGHT / 2
    
    for i in 0..<CLUSTER_COUNT {
        cluster_generation(Tile(rand.int31_max(4)))
    }
    for v,i in count_clusters_sizes {
        fmt.println(i, ":", v)
    }
    
    for !rl.WindowShouldClose() {
        rl.BeginDrawing()
        rl.ClearBackground(rl.GetColor(0x202020FF))
        // rl.DrawTextEx(font, "abcdefghijklmnopqrstuvwxyz", {0, 0}, 80, 0, rl.WHITE)
        // rl.DrawTextEx(font, "ABCDEFGHIJKLMNOPQRSTUVWXYZ", {0, 80}, 80, 0, rl.WHITE)        
        if rl.IsKeyDown(rl.KeyboardKey.UP) && player.y > 0 {
            player.y -= 1
        }
        if rl.IsKeyDown(rl.KeyboardKey.RIGHT) && player.x < WORLD_WIDTH - 1{
            player.x += 1
        }
        if rl.IsKeyDown(rl.KeyboardKey.LEFT) && player.x > 0{
            player.x -= 1 
        }
        if rl.IsKeyDown(rl.KeyboardKey.DOWN) && player.y < WORLD_HEIGHT - 1{
            player.y += 1
        }
        if rl.IsKeyDown(rl.KeyboardKey.MINUS) {
            // scale = scale*0.9
            scale = max(1, scale*0.9)
            rows = i32(f32(WINDOW_HEIGHT) / (f32(char_height) * scale))
            cols = i32(f32(WINDOW_WIDTH) / (f32(char_width) * scale))
        }
        if rl.IsKeyDown(rl.KeyboardKey.EQUAL) {
            // scale = scale*1.1
            scale = min(scale*1.1, 20)
            rows = i32(f32(WINDOW_HEIGHT) / (f32(char_height) * scale))
            cols = i32(f32(WINDOW_WIDTH) / (f32(char_width) * scale))
        }

        for i : i32 = max(0, player.x - cols/2); i < min(player.x + cols/2, WORLD_WIDTH); i += 1 {
            for j : i32 = max(0, player.y - rows/2); j < min(player.y + rows/2, WORLD_HEIGHT); j += 1 {
                #partial switch world[i][j] {
                    case .NONE:
                        draw_char(' ', {f32((i - player.x + cols/2) * char_width) * scale, f32((j - player.y + rows/2) * char_height) * scale}, scale)
                    case .IRON:
                        draw_char('I', {f32((i - player.x + cols/2) * char_width) * scale, f32((j - player.y + rows/2) * char_height) * scale}, scale)
                    case .TUNGSTEN:
                        draw_char('T', {f32((i - player.x + cols/2) * char_width) * scale, f32((j - player.y + rows/2) * char_height) * scale}, scale)
                    case .COAL:
                        draw_char('C', {f32((i - player.x + cols/2) * char_width) * scale, f32((j - player.y + rows/2) * char_height) * scale}, scale)
                    case:
                        unimplemented("BRUH!")
                }
            }
        }


        // PLAYER
        draw_char('@', {f32(cols/2 * char_width) * scale,  f32(rows/2 * char_height) * scale}, scale)

        // SETKA
        for i : i32 = 0; i < cols; i += 1 {
            if (i == 0 || i == cols - 1) {
                draw_char('+', {(f32(i * char_width) * scale), 0}, f32(scale))
            } else {
                draw_char('-', {(f32(i * char_width) * scale), 0}, f32(scale))
            }
        }
        for i : i32 = 0; i < cols; i += 1 {
            if (i == 0 || i == cols - 1) {
                draw_char('+', {(f32(i * char_width) * scale), f32((rows - 1) * char_height) * scale}, scale)
            } else {
                draw_char('-', {(f32(i * char_width) * scale), f32((rows - 1) * char_height) * scale}, scale)
            }
        }
        for i : i32 = 1; i < rows - 1; i += 1 {
            draw_char('|', {0, cast(f32) (i * char_height) * scale}, scale)
        }
        for i : i32 = 1; i < rows - 1; i += 1 {
            draw_char('|', {(f32((cols - 1) * char_width) * scale), f32(i * char_height) * scale}, scale)
        }
        rl.DrawFPS(14,14)
        rl.EndDrawing()
    }    
}
