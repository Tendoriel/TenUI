"""Render the original, mirrored Midnight hardware for TenUI (requires Pillow)."""
from pathlib import Path
from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parents[2] / "TenUI/Media/UI"
S = 4
steel, light, shadow = "#8794B2", "#E6EBFF", "#242637"
bronze, gold, violet, cyan = "#795832", "#F9CE83", "#AD83FF", "#7ADEFF"


class Plate:
    def __init__(self, width, height):
        self.size = width, height
        self.image = Image.new("RGBA", (width*S, height*S))
        self.pen = ImageDraw.Draw(self.image)

    def polygon(self, points, color):
        self.pen.polygon([(round(x*S), round(y*S)) for x, y in points], fill=color)

    def line(self, points, color, width=1):
        self.pen.line([(round(x*S), round(y*S)) for x, y in points], fill=color, width=max(1,round(width*S)))

    def sphere(self, x, y, radius):
        for i, color in enumerate([shadow, steel, bronze, gold, shadow]):
            r = radius*(1-i*.055)
            self.pen.ellipse(((x-r)*S,(y-r)*S,(x+r)*S,(y+r)*S), fill=color)
        r = radius*.70
        for i in range(30):
            t=i/29
            a,b=x-r*.35*t,y-r*.40*t
            k=r*(1-t)
            rgb=(int(31+110*t*t),int(12+69*t*t),int(57+170*t))
            self.pen.ellipse(((a-k)*S,(b-k)*S,(a+k)*S,(b+k)*S),fill=rgb)
        self.line([(x-r*.48,y-r*.34),(x-r*.25,y-r*.53)],light,r*.16)

    def gem(self, x, y, w, h):
        pts=[(x,y-h),(x+w,y),(x,y+h),(x-w,y)]
        self.polygon(pts,shadow)
        for i,c in enumerate([steel,"#454366","#6F609F",light]):
            self.polygon([pts[i],pts[(i+1)%4],(x,y)],c)
        self.polygon([(x,y-h*.62),(x+w*.48,y),(x,y+h*.64),(x-w*.50,y)],violet)
        self.line([(x,y-h*.56),(x-w*.42,y),(x,y+h*.53)],cyan,.8)

    def save(self,name):
        self.image.resize(self.size, Image.Resampling.LANCZOS).save(OUT/(name+".tga"))


def window_trim():
    # Northwest bracket: two nested mitres, a triangular brace and a square jewel.
    # The long rails continue on the window's edges; the corners never stretch.
    c = Plate(128, 128)
    c.polygon([(1,1),(125,1),(114,13),(54,13),(13,54),(13,113),(1,125)], "#151321")
    c.polygon([(4,4),(122,4),(113,11),(50,11),(11,50),(11,113),(4,121)], "#74778D")
    c.line([(4,120),(4,4),(120,4)], "#D0D0E2", 2)
    c.line([(10,109),(10,50),(50,10),(109,10)], "#B4AFCA", 1.5)
    c.polygon([(15,17),(45,17),(17,45),(17,34),(31,21),(15,21)], "#ADA9C0")
    c.line([(18,43),(43,18),(15,18)], "#E4DFF0", 1.3)
    c.polygon([(17,53),(53,17),(92,17),(81,24),(55,24),(24,55),(24,79),(17,91)], "#25213B")
    c.line([(19,84),(19,53),(53,19),(85,19)], "#8A839F", 2)
    c.line([(24,73),(24,55),(55,24),(74,24)], "#B5ACC7", 1.4)
    c.polygon([(8,8),(26,8),(26,26),(8,26)], "#191424")
    c.line([(8,26),(8,8),(26,8)], light, 2)
    c.line([(26,8),(26,26),(8,26)], steel, 2)
    c.gem(17,17,7,8)
    c.save("window_mitre")
    c = Plate(64,128)
    c.polygon([(17,0),(34,15),(34,39),(60,64),(34,89),(34,114),(17,128),
               (17,91),(42,64),(17,37)], "#232031")
    c.line([(20,4),(32,16),(32,41),(55,64),(32,87),(32,112),(20,124)], steel, 3)
    c.line([(21,17),(21,37),(47,64),(21,91),(21,111)], "#D1CADA", 2)
    c.gem(18,64,14,16)
    c.save("window_keystone")
    c = Plate(128,32)
    for flip in [1,-1]:
        def shape(points):
            return [(64+flip*x,y) for x,y in points]
        c.polygon(shape([(0,28),(23,5),(59,5),(50,12),(28,12),(12,29)]), "#292438")
        c.line(shape([(1,26),(23,5),(59,5)]), "#C5BDD2", 2)
        c.line(shape([(10,27),(27,11),(50,11)]), steel, 2)
    c.gem(64,12,6,7)
    c.save("window_lintel")


def ornaments():
    c=Plate(64,64)
    for transpose in [False,True]:
        def path(points): return [(y,x) if transpose else (x,y) for x,y in points]
        c.polygon(path([(4,5),(62,5),(40,11),(32,17),(13,13)]),shadow)
        c.polygon(path([(5,5),(61,5),(36,9),(28,13)]),steel)
        c.line(path([(5,5),(60,5),(39,8)]),light,.9)
        c.line(path([(15,15),(32,15),(43,9),(57,8)]),bronze,1.3)
    c.gem(17,17,12,16)
    c.sphere(11,11,8)
    c.sphere(31,9,2.5)
    c.sphere(9,31,2.5)
    c.save("corner_void_orb")
    c=Plate(32,64)
    c.polygon([(3,0),(26,30),(26,34),(3,64),(12,38),(16,32),(12,26)],shadow)
    c.line([(3,1),(25,32),(3,63)],light,1.5)
    c.line([(5,10),(19,32),(5,54)],steel,2)
    c.gem(21,32,6,11)
    c.save("bracket_alleria_chevron")
    c=Plate(32,32)
    c.line([(2,31),(2,2),(31,2)],light)
    c.line([(6,23),(6,8),(8,6),(23,6)],steel)
    c.gem(7,7,3,4)
    c.save("card_corner_inlay")
    c=Plate(32,32)
    c.gem(16,16,9,15)
    c.save("thumb_void_diamond")
    c=Plate(512,32)
    for i in range(256):
        t=i/255
        for x,color in [(i,(140,69,255)),(511-i,(56,200,255))]:
            for offset,alpha in [(3,10),(2,28),(1,72),(0,205)]:
                c.line([(x,16-offset),(x+1,16-offset)],(*color,int(alpha*(.15+.85*t))))
                if offset: c.line([(x,16+offset),(x+1,16+offset)],(*color,int(alpha*(.15+.85*t))))
    c.sphere(256,16,12)
    c.gem(256,16,5,15)
    c.save("divider_clash_eclipse")
    c=Plate(128,32)
    for sign in [-1,1]:
        def wing(points): return [(64+sign*x,y) for x,y in points]
        c.polygon(wing([(0,11),(62,8),(32,14),(21,23),(19,15),(12,25),(10,17),(5,28)]),shadow)
        c.line(wing([(0,12),(61,8),(30,13),(21,21)]),steel,1.4)
        c.line(wing([(1,14),(29,12),(14,16),(11,22)]),gold,.8)
    c.gem(64,15,11,12)
    c.sphere(64,15,5)
    c.save("header_eye_clasp")


if __name__ == "__main__":
    ornaments()
    window_trim()
