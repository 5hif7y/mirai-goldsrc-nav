package goldsrc_nav_file

import "core:bytes"
import "core:encoding/json"
import "core:testing"

// A .nav of two areas written in code: places, connections both ways, a
// hiding spot, an approach, an encounter and four bytes after the areas.
@(private="file")
two_areas :: proc() -> []u8 {
    nav:=Nav{
        format="goldsrc-nav",version=5,magic="0xfeedface",bsp_size=1234,
        places={"BombsiteA\x00","Middle"},
        areas={
            {id=1,flags={"crouch","precise"},lo={0,0,0},hi={64,64,0},corner_z={0,0},
             connections={east={2}},
             hiding_spots={{id=7,position={32,32,0},flags={"in_cover","ideal_sniper_spot"}}},
             approach={{here=1,prev=2,prev_how="west",next=2,next_how="ladder_up"}},
             encounters={{from=2,from_dir="west",to=2,to_dir="east",spots={{id=7,t=128}}}},
             place=1},
            {id=2,lo={64,0,8},hi={128,64,8},corner_z={8,8},connections={west={1}},place=2},
        },
        trailing_base64="AQIDBA==",
    }
    return write(nav,context.temp_allocator)
}

@(test)
a_nav_read_and_written_gives_back_its_bytes :: proc(t:^testing.T) {
    context.allocator=context.temp_allocator
    original:=two_areas()
    nav,message,ok:=read(original)
    if !testing.expectf(t,ok,"%s",message) {return}
    testing.expect_value(t,len(nav.areas),2)
    testing.expect(t,nav.areas[0].approach[0].next_how=="ladder_up" && nav.areas[0].hiding_spots[0].flags[1]=="ideal_sniper_spot","names of flags and ways")
    testing.expect(t,bytes.equal(write(nav),original),"read then write gives the same bytes")
    s:=summary(nav)
    testing.expect(t,s.areas==2 && s.connections==2 && s.hiding_spots==1 && s.encounters==1 && s.places==2,"the summary counts")
}

// Through the JSON of the API and back: what an agent edits.
@(test)
a_nav_through_json_gives_back_its_bytes :: proc(t:^testing.T) {
    context.allocator=context.temp_allocator
    original:=two_areas()
    nav,message,ok:=read(original)
    if !testing.expectf(t,ok,"%s",message) {return}
    text,error:=json.marshal(nav,{pretty=true})
    if !testing.expectf(t,error==nil,"%v",error) {return}
    back:Nav
    if !testing.expect(t,json.unmarshal(text,&back)==nil) {return}
    testing.expect(t,bytes.equal(write(back),original),"the JSON keeps every byte of the .nav")
}

@(test)
a_file_that_is_not_a_nav_is_refused :: proc(t:^testing.T) {
    _,_,ok:=read([]u8{1,2,3,4,5,0,0,0},context.temp_allocator)
    testing.expect(t,!ok)
}
