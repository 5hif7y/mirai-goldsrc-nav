package goldsrc_nav_file

import "core:encoding/base64"
import "core:encoding/endian"
import "core:fmt"
import "core:slice"

// The .nav of the bots of GoldSrc (Counter-Strike 1.6, Condition Zero), as
// game_shared/bot/nav_file.cpp of ReGameDLL_CS writes it, up to version 5:
//
//   u32 magic 0xFEEDFACE, u32 version, u32 bsp_size (version 4 on)
//   u16 place_count, (u16 len, bytes[len]) × place_count        (version 5)
//   u32 area_count, and each area:
//     u32 id, u8 flags, 6×f32 extent (lo, hi), f32 ne_z, f32 sw_z
//     4×(u32 count, count×u32 area id)             north east south west
//     u8 hiding spots, (u32 id, 3×f32 position, u8 flags) each
//     u8 approaches, (u32 here, u32 prev, u8 prev_how, u32 next, u8 next_how) each
//     u32 encounters, (u32 from, u8 from_dir, u32 to, u8 to_dir, u8 spots, (u32 id, u8 t) × spots) each
//     u16 place                                    (version 5)
//
// Nav is the same information in the order of the file, with flags and ways of
// traversing by name: what the JSON of the API is, so that an agent reads and
// edits it and writes the .nav back. Writing what was read gives back the same
// bytes, including what some editors leave after the areas.

MAGIC :: 0xFEEDFACE
VERSION :: 5
DIRECTIONS :: [4]string{"north","east","south","west"}
TRAVERSE :: [7]string{"north","east","south","west","ladder_up","ladder_down","jump"}
TRAVERSE_INVALID :: "invalid" // 7, NUM_TRAVERSE_TYPES: an approach without a way
AREA_FLAGS :: [4]Flag{{"crouch",0x01},{"jump",0x02},{"precise",0x04},{"no_jump",0x08}}
HIDING_FLAGS :: [3]Flag{{"in_cover",0x01},{"good_sniper_spot",0x02},{"ideal_sniper_spot",0x04}}

Flag :: struct {name:string,bit:u8}

Corner_Z :: struct {
    ne:f32 `json:"ne"`, // height of the corner (hi.x, lo.y)
    sw:f32 `json:"sw"`, // height of the corner (lo.x, hi.y)
}

Connections :: struct {
    north:[]u32 `json:"north"`,
    east:[]u32 `json:"east"`,
    south:[]u32 `json:"south"`,
    west:[]u32 `json:"west"`,
}

Hiding_Spot :: struct {
    id:u32 `json:"id"`,
    position:[3]f32 `json:"position"`,
    flags:[]string `json:"flags"`,
}

Approach :: struct {
    here:u32 `json:"here"`,
    prev:u32 `json:"prev"`,
    prev_how:string `json:"prev_how"`,
    next:u32 `json:"next"`,
    next_how:string `json:"next_how"`,
}

Encounter_Spot :: struct {
    id:u32 `json:"id"`,
    t:u8 `json:"t"`,
}

Encounter :: struct {
    from:u32 `json:"from"`,
    from_dir:string `json:"from_dir"`,
    to:u32 `json:"to"`,
    to_dir:string `json:"to_dir"`,
    spots:[]Encounter_Spot `json:"spots"`,
}

Area :: struct {
    id:u32 `json:"id"`,
    flags:[]string `json:"flags"`,
    lo:[3]f32 `json:"lo"`,
    hi:[3]f32 `json:"hi"`,
    corner_z:Corner_Z `json:"corner_z"`,
    connections:Connections `json:"connections"`,
    hiding_spots:[]Hiding_Spot `json:"hiding_spots"`,
    approach:[]Approach `json:"approach"`,
    encounters:[]Encounter `json:"encounters"`,
    place:u16 `json:"place"`,
}

Nav :: struct {
    format:string `json:"format"`,
    version:u32 `json:"version"`,
    magic:string `json:"magic"`,
    bsp_size:u32 `json:"bsp_size"`, // of the .bsp it was made for
    places:[]string `json:"places"`,  // as the file has them: the length may count the final NUL
    areas:[]Area `json:"areas"`,
    trailing_base64:string `json:"trailing_base64,omitempty"`, // what some editors leave after the areas
}

@(private)
Reader :: struct {d:[]u8,at:int,short:bool}

@(private) u8_ :: proc(r:^Reader) -> u8 {if r.at+1>len(r.d) {r.short=true;return 0};v:=r.d[r.at];r.at+=1;return v}
@(private) u16_ :: proc(r:^Reader) -> u16 {if r.at+2>len(r.d) {r.short=true;return 0};v,_:=endian.get_u16(r.d[r.at:r.at+2],.Little);r.at+=2;return v}
@(private) u32_ :: proc(r:^Reader) -> u32 {if r.at+4>len(r.d) {r.short=true;return 0};v,_:=endian.get_u32(r.d[r.at:r.at+4],.Little);r.at+=4;return v}
@(private) f32_ :: proc(r:^Reader) -> f32 {if r.at+4>len(r.d) {r.short=true;return 0};v,_:=endian.get_f32(r.d[r.at:r.at+4],.Little);r.at+=4;return v}

@(private)
flag_names :: proc(value:u8,table:[]Flag) -> []string {
    out:=make([dynamic]string)
    for f in table {if value&f.bit!=0 {append(&out,f.name)}}
    return out[:]
}

@(private)
flag_bits :: proc(names:[]string,table:[]Flag) -> u8 {
    bits:u8
    for f in table {if slice.contains(names,f.name) {bits|=f.bit}}
    return bits
}

@(private)
traverse_name :: proc(value:u8) -> string {
    names:=TRAVERSE
    return names[value] if int(value)<len(names) else TRAVERSE_INVALID
}

@(private)
traverse_value :: proc(name:string) -> u8 {
    names:=TRAVERSE
    for n,i in names {if n==name {return u8(i)}}
    return u8(len(names))
}

@(private)
direction_index :: proc(name:string) -> u8 {
    names:=DIRECTIONS
    for n,i in names {if n==name {return u8(i)}}
    return 0
}

// Reads a .nav; message says why not.
read :: proc(data:[]u8,allocator:=context.allocator) -> (nav:Nav,message:string,ok:bool) {
    context.allocator=allocator
    r:=Reader{d=data}
    area_flags,hiding_flags:=AREA_FLAGS,HIDING_FLAGS
    magic,version:=u32_(&r),u32_(&r)
    if magic!=MAGIC {return nav,fmt.tprintf("not a .nav of GoldSrc (magic %#x)",magic),false}
    if version>VERSION {return nav,fmt.tprintf("version %d: this reads up to %d",version,VERSION),false}
    nav.format,nav.version,nav.magic="goldsrc-nav",version,fmt.aprintf("%#x",magic)
    if version>=4 {nav.bsp_size=u32_(&r)}
    places:=make([dynamic]string)
    if version>=VERSION {
        place_count:=u16_(&r)
        for _ in 0..<place_count {
            length:=int(u16_(&r))
            if r.at+length>len(data) {r.short=true;break}
            append(&places,string(slice.clone(data[r.at:r.at+length])))
            r.at+=length
        }
    }
    nav.places=places[:]
    count:=u32_(&r)
    if int(count)>len(data) {return nav,"the count of areas is larger than the file",false}
    areas:=make([dynamic]Area)
    directions:=DIRECTIONS
    for _ in 0..<count {
        if r.short {break}
        a:Area
        a.id=u32_(&r)
        a.flags=flag_names(u8_(&r),area_flags[:])
        for k in 0..<3 {a.lo[k]=f32_(&r)}
        for k in 0..<3 {a.hi[k]=f32_(&r)}
        a.corner_z={f32_(&r),f32_(&r)}
        for d in 0..<len(directions) {
            n:=u32_(&r)
            if int(n)>len(data) {r.short=true;break}
            ids:=make([]u32,n)
            for &id in ids {id=u32_(&r)}
            switch d {
            case 0: a.connections.north=ids
            case 1: a.connections.east=ids
            case 2: a.connections.south=ids
            case 3: a.connections.west=ids
            }
        }
        spots:=make([]Hiding_Spot,u8_(&r))
        for &s in spots {
            s.id=u32_(&r)
            for k in 0..<3 {s.position[k]=f32_(&r)}
            s.flags=flag_names(u8_(&r),hiding_flags[:])
        }
        a.hiding_spots=spots
        approach:=make([]Approach,u8_(&r))
        for &e in approach {
            e.here,e.prev=u32_(&r),u32_(&r)
            e.prev_how=traverse_name(u8_(&r))
            e.next=u32_(&r)
            e.next_how=traverse_name(u8_(&r))
        }
        a.approach=approach
        n:=u32_(&r)
        if int(n)>len(data) {r.short=true;break}
        encounters:=make([]Encounter,n)
        for &e in encounters {
            e.from=u32_(&r)
            e.from_dir=directions[min(int(u8_(&r)),3)]
            e.to=u32_(&r)
            e.to_dir=directions[min(int(u8_(&r)),3)]
            e.spots=make([]Encounter_Spot,u8_(&r))
            for &s in e.spots {s.id=u32_(&r);s.t=u8_(&r)}
        }
        a.encounters=encounters
        if version>=VERSION {a.place=u16_(&r)}
        append(&areas,a)
    }
    if r.short {return nav,"the file ends inside an area",false}
    nav.areas=areas[:]
    if r.at<len(data) {nav.trailing_base64=base64.encode(data[r.at:])}
    return nav,"",true
}

// The bytes of a .nav: what read gives, written back, gives the same bytes.
write :: proc(nav:Nav,allocator:=context.allocator) -> []u8 {
    out:=make([dynamic]u8,allocator)
    area_flags,hiding_flags:=AREA_FLAGS,HIDING_FLAGS
    u8w :: proc(out:^[dynamic]u8,v:u8) {append(out,v)}
    u16w :: proc(out:^[dynamic]u8,v:u16) {x:[2]u8;endian.put_u16(x[:],.Little,v);append(out,..x[:])}
    u32w :: proc(out:^[dynamic]u8,v:u32) {x:[4]u8;endian.put_u32(x[:],.Little,v);append(out,..x[:])}
    f32w :: proc(out:^[dynamic]u8,v:f32) {x:[4]u8;endian.put_f32(x[:],.Little,v);append(out,..x[:])}
    version:=nav.version if nav.version!=0 else VERSION
    u32w(&out,MAGIC)
    u32w(&out,version)
    if version>=4 {u32w(&out,nav.bsp_size)}
    if version>=VERSION {
        u16w(&out,u16(len(nav.places)))
        for name in nav.places {
            u16w(&out,u16(len(name)))
            append(&out,..transmute([]u8)name)
        }
    }
    u32w(&out,u32(len(nav.areas)))
    for a in nav.areas {
        u32w(&out,a.id)
        u8w(&out,flag_bits(a.flags,area_flags[:]))
        for v in a.lo {f32w(&out,v)}
        for v in a.hi {f32w(&out,v)}
        f32w(&out,a.corner_z.ne)
        f32w(&out,a.corner_z.sw)
        for ids in ([4][]u32{a.connections.north,a.connections.east,a.connections.south,a.connections.west}) {
            u32w(&out,u32(len(ids)))
            for id in ids {u32w(&out,id)}
        }
        spots:=a.hiding_spots[:min(len(a.hiding_spots),255)]
        u8w(&out,u8(len(spots)))
        for s in spots {
            u32w(&out,s.id)
            for v in s.position {f32w(&out,v)}
            u8w(&out,flag_bits(s.flags,hiding_flags[:]))
        }
        u8w(&out,u8(len(a.approach)))
        for e in a.approach {
            u32w(&out,e.here)
            u32w(&out,e.prev)
            u8w(&out,traverse_value(e.prev_how))
            u32w(&out,e.next)
            u8w(&out,traverse_value(e.next_how))
        }
        u32w(&out,u32(len(a.encounters)))
        for e in a.encounters {
            u32w(&out,e.from)
            u8w(&out,direction_index(e.from_dir))
            u32w(&out,e.to)
            u8w(&out,direction_index(e.to_dir))
            u8w(&out,u8(len(e.spots)))
            for s in e.spots {u32w(&out,s.id);u8w(&out,s.t)}
        }
        if version>=VERSION {u16w(&out,a.place)}
    }
    if nav.trailing_base64!="" {
        if trailing,error:=base64.decode(nav.trailing_base64,allocator=context.temp_allocator);error==nil {append(&out,..trailing)}
    }
    return out[:]
}

Summary :: struct {
    areas,connections,hiding_spots,approaches,encounters,places:int,
    lo,hi:[3]f32,
}

summary :: proc(nav:Nav) -> (s:Summary) {
    s.areas,s.places=len(nav.areas),len(nav.places)
    s.lo,s.hi={max(f32),max(f32),max(f32)},{min(f32),min(f32),min(f32)}
    for a in nav.areas {
        s.connections+=len(a.connections.north)+len(a.connections.east)+len(a.connections.south)+len(a.connections.west)
        s.hiding_spots+=len(a.hiding_spots)
        s.approaches+=len(a.approach)
        s.encounters+=len(a.encounters)
        for k in 0..<3 {s.lo[k]=min(s.lo[k],a.lo[k]);s.hi[k]=max(s.hi[k],a.hi[k])}
    }
    if s.areas==0 {s.lo,s.hi={},{}}
    return
}
