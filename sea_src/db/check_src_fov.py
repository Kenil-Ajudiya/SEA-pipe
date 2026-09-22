#!/usr/bin/env python

from __future__ import print_function

import os,sys
from astropy import wcs
from astropy.io import fits
from astropy.coordinates import SkyCoord
import astropy.units as u

from argparse import ArgumentParser

def check_coords(w, coords):
    x, y =  w.all_world2pix(coords.ra.deg,coords.dec.deg,0)
    if 0 < x < w._naxis[0] and 0 < y < w._naxis[1]:
        return True
    else:
        return False

if __name__ == "__main__":
    usage="Usage: %prog [args] <file>\n"
    parser = ArgumentParser()
    parser.add_argument('-f','--file',dest="file", default=None,
                      help="Fits image to check <FILE>",metavar="FILE")
    parser.add_argument('-p','--pos', dest="position", default=None, 
                      help="RA and Dec to check distance to source, format=x,y in deg",nargs=2)
    parser.add_argument('-s','--source',dest="source", default=None,
                      help="Source to measure")
    parser.add_argument('-g', '--galcheck', dest="galcheck", default=False, 
                        action="store_true", help="Do you want to check if it's a galactic pointing?")
    args = parser.parse_args()

    sources = {'Crab': '05:34:31.94 +22:00:52.2', 'PicA': '05:19:49.7229 -45:46:43.853', 'HydA': '09:18:05.651 -12:05:43.99', 'HerA': '16:51:11.4 +04:59:20' , 'VirA': '12:30:49.42338 +12:23:28.0439' , 'CygA': '19:59:28.35663 +40:44:02.0970' ,'CasA': '23:23:24.000 +58:48:54.00', 'CenA': '13:25:28.0 -43:01:09.00'}

    if args.file is None and args.position is None:
        print(f"File is {args.file} and Position is {args.position}")
        sys.exit(1)

    if args.file is not None and os.path.exists(args.file):
        hdu_in = fits.open(args.file)
        w = wcs.WCS(hdu_in[0].header,naxis=2)
    elif args.file is None: 
        pass
        # print("Not using file...")
    else:
        print(args.file+" does not exist.")
        sys.exit(1)

    if args.position is not None: 
        try:
            ra_ref, dec_ref = float(args.position[0]), float(args.position[1])
            w=SkyCoord(ra_ref,dec_ref, frame="icrs", unit="deg")
        except:
            print("Cannot understand coords?")
            sys.exit(1)        
    if args.galcheck is True: 
        galcoords = w.galactic 
        if abs(galcoords.b.value) <= 10.: 
            print("True")
        else: 
            print("False")
    else:
        if args.source is None: 
            # print("No source provided! going to go through all and see if any are in the fov")
            checks = []
            for src, coords in sources.items():
                pos = SkyCoord([sources[src]], unit=(u.hourangle, u.deg))
                if args.position is None: 
                    checks.append(check_coords(w,pos))
                elif args.file is None: 
                    sep=w.separation(pos)
                    if float(sep.deg) <= 30:
                        checks.append(True)
                    else: 
                        checks.append(False)
            if any(checks):
                print("True")
            else:
                print("False")
        elif args.source in sources:
            pos = SkyCoord([sources[args.source]], unit=(u.hourangle, u.deg))
            if args.position is None:
                checks = check_coords(w,pos)
            elif args.file is None: 
                sep=w.separation(pos)
                if float(sep.deg) <= 30:
                    checks = True
                else: 
                    checks = False
            if checks:
                print("True")
            else: 
                print("False")
        else:
            print(args.source+" not found in dictionary, which only contains: ", sources.keys())
            sys.exit(1)



    # if args.position is None: 
    #     w = wcs.WCS(hdu_in[0].header,naxis=2)
    #     if check_coords(w, pos):
    #         print("True")
    #     else:
    #         print("False")
    # elif args.file is None: 
    #     w=SkyCoord(ra_ref,dec_ref, frame="icrs", unit="deg")
    #     sep=w.separation(pos)
    #     if float(sep.deg) <= 30:
    #         print("True")
    #     else: 
    #         print("False")
