package renderlink

Color_Component :: u8
Color :: [4]Color_Component

DEFAULT_COLOR :: COLOR_BLACK

color_from_integer :: proc(#any_int color: u32) -> Color {
    return {
        Color_Component((color & 0xff000000) >> 24),
        Color_Component((color & 0x00ff0000) >> 16),
        Color_Component((color & 0x0000ff00) >> 8),
        Color_Component((color & 0x000000ff) >> 0),
    }
}

color_to_integer :: proc(color: Color) -> u32 {
    return u32(((color.r << 24) | (color.g << 16) | (color.b << 8) | color.a))
}

COLOR_ALICE_BLUE    :: Color{ 240, 248, 255, 255 }
COLOR_ANTIQUE_WHITE :: Color{ 250, 235, 215, 255 }
COLOR_AQUAMARINE    :: Color{ 125, 255, 212, 255 }
COLOR_AZURE         :: Color{ 240, 255, 255, 255 }
COLOR_BEIGE         :: Color{ 212, 176, 130, 255 }
COLOR_BISQUE        :: Color{ 255, 228, 196, 255 }
COLOR_BLACK         :: Color{ 0, 0, 0, 255 }
COLOR_BLANK         :: Color{ 0, 0, 0, 0 }
COLOR_BLUE          :: Color{ 0, 120, 242, 255 }
COLOR_BROWN         :: Color{ 127, 107, 79, 255 }
COLOR_CRIMSON       :: Color{ 220, 20, 61, 255 }
COLOR_CYAN          :: Color{ 0, 255, 255, 255 }
COLOR_DARKBLUE      :: Color{ 0, 82, 171, 255 }
COLOR_DARKBROWN     :: Color{ 76, 63, 46, 255 }
COLOR_DARKGRAY      :: Color{ 79, 79, 79, 255 }
COLOR_DARKGREEN     :: Color{ 0, 117, 43, 255 }
COLOR_DARKPURPLE    :: Color{ 112, 31, 125, 255 }
COLOR_DARKRED       :: Color{ 117, 20, 31, 255 }
COLOR_DARK_GRAY     :: Color{ 64, 64, 64, 255 }
COLOR_DARK_GREEN    :: Color{ 0, 127, 0, 255 }
COLOR_FUCHSIA       :: Color{ 255, 0, 255, 255 }
COLOR_GOLD          :: Color{ 255, 204, 0, 255 }
COLOR_GRAY          :: Color{ 130, 130, 130, 255 }
COLOR_GREEN         :: Color{ 0, 227, 48, 255 }
COLOR_INDIGO        :: Color{ 74, 0, 130, 255 }
COLOR_LIGHTGRAY     :: Color{ 199, 199, 199, 255 }
COLOR_LIME          :: Color{ 0, 158, 46, 255 }
COLOR_LIME_GREEN    :: Color{ 51, 204, 51, 255 }
COLOR_MAGENTA       :: Color{ 255, 0, 255, 255 }
COLOR_MAROON        :: Color{ 191, 33, 56, 255 }
COLOR_MIDNIGHT_BLUE :: Color{ 25, 25, 112, 255 }
COLOR_NAVY          :: Color{ 0, 0, 127, 255 }
COLOR_OLIVE         :: Color{ 127, 127, 0, 255 }
COLOR_ORANGE        :: Color{ 255, 161, 0, 255 }
COLOR_ORANGE_RED    :: Color{ 255, 69, 0, 255 }
COLOR_PINK          :: Color{ 255, 110, 194, 255 }
COLOR_PURPLE        :: Color{ 199, 122, 255, 255 }
COLOR_RED           :: Color{ 230, 41, 56, 255 }
COLOR_SALMON        :: Color{ 250, 127, 115, 255 }
COLOR_SEA_GREEN     :: Color{ 46, 139, 87, 255 }
COLOR_SILVER        :: Color{ 191, 191, 191, 255 }
COLOR_SKYBLUE       :: Color{ 102, 191, 255, 255 }
COLOR_TEAL          :: Color{ 0, 127, 127, 255 }
COLOR_TOMATO        :: Color{ 255, 99, 71, 255 }
COLOR_TRANSPARENT   :: Color{ 0, 0, 0, 0 }
COLOR_TURQUOISE     :: Color{ 64, 224, 208, 255 }
COLOR_VIOLET        :: Color{ 135, 61, 191, 255 }
COLOR_WHITE         :: Color{ 255, 255, 255, 255 }
COLOR_YELLOW        :: Color{ 253, 250, 0, 255 }
COLOR_YELLOW_GREEN  :: Color{ 153, 204, 51, 255 }
