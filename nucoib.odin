package nucoib

import "core:fmt"
import "core:strings"
import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

COLS : i32 : 18
ROWS : i32 : 7
WINDOW_WIDTH : i32 : 800
WINDOW_HEIGHT : i32 : 600
SCALE : f32 : 2 
WORLD_WIDTH : i32 : 70
WORLD_HEIGHT : i32 : 50

Player :: struct { 
    x : i32,
    y : i32,
}

Tile :: enum {
    NONE,
    IRON,
    TUNGSTEN,
    COAL,
}

world : [WORLD_WIDTH][WORLD_HEIGHT]Tile 

char_width : i32 
char_height : i32
font_texture : rl.Texture2D

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
    
    // font : rl.Font = rl.LoadFont("./Riglos.ttf")
    font_texture = rl.LoadTexture("./charmap-oldschool_white.png")
    char_width = font_texture.width / COLS;
    char_height = font_texture.height / ROWS;
    
    rows : i32 = i32(f32(WINDOW_HEIGHT) / (f32(char_height) * SCALE));
    cols : i32 = i32(f32(WINDOW_WIDTH) / (f32(char_width) * SCALE));

    
    player.x = cols / 2
    player.y = rows / 2
    
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

        for i : i32 = 0; i < WORLD_WIDTH; i += 1 {
            for j : i32 = 0; j < WORLD_HEIGHT; j += 1 {
                 #partial switch world[i][j] {
                    case .NONE:
                        draw_char(' ', {f32((i - player.x + cols/2) * char_width) * SCALE, f32((j - player.y + rows/2) * char_height) * SCALE}, SCALE)
                    case:
                        unimplemented("BRUH!")
                }
            }
        }

        // PLAYER
        draw_char('@', {f32(cols/2 * char_width) * SCALE,  f32(rows/2 * char_height) * SCALE}, SCALE)

        // SETKA
        for i : i32 = 0; i < cols; i += 1 {
            if (i == 0 || i == cols - 1) {
                draw_char('+', {(f32(i * char_width) * SCALE), 0}, f32(SCALE))
            } else {
                draw_char('-', {(f32(i * char_width) * SCALE), 0}, f32(SCALE))
            }
        }
        for i : i32 = 0; i < cols; i += 1 {
            if (i == 0 || i == cols - 1) {
                draw_char('+', {(f32(i * char_width) * SCALE), f32((rows - 1) * char_height) * SCALE}, SCALE)
            } else {
                draw_char('-', {(f32(i * char_width) * SCALE), f32((rows - 1) * char_height) * SCALE}, SCALE)
            }
        }
        for i : i32 = 1; i < rows - 1; i += 1 {
            draw_char('|', {0, cast(f32) (i * char_height) * SCALE}, SCALE)
        }
        for i : i32 = 1; i < rows - 1; i += 1 {
            draw_char('|', {(f32((cols - 1) * char_width) * SCALE), f32(i * char_height) * SCALE}, SCALE)
        }
        
        rl.EndDrawing()
    }    
}
