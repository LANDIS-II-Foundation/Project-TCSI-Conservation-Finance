#Create ignitions maps for SCRPPLE
# From Short et al. data and a boundary box of the study area

library("raster")
library("sf")
library("sp")
library("spatstat")


setwd("C:/Users/Sam/Documents/Research/California forest economics")

# raster to get bounding box from
mask <- raster("./masks_boundaries/mask.tif")
crs(mask) <- "EPSG:9311" #replaces deprecated epsg:2163; US National Atlas Equal Area
#-------------------------------------------------------------------------------
#import Short data

sf::st_layers("./Parameterization/calibration data/short_ignitions/Data/FPA_FOD_20210617.gdb")
short <- sf::st_read("./Parameterization/calibration data/short_ignitions/Data/FPA_FOD_20210617.gdb", layer = "Fires")
st_geometry_type(short)
st_crs(short)
short_full <- st_transform(short, 9311)

#make a bounding box for Short data
bound <- extent(mask)
bound[c(1,3)] <- bound[c(1,3)] - 30000
bound[c(2,4)] <- bound[c(2,4)] + 30000

bound <- as(bound, 'SpatialPolygons') %>% 
  st_as_sf() %>%
  st_set_crs(9311) 


short_subset <- sf::st_intersection(short, bound)

lightning_ignitions <- short_subset[short_subset$NWCG_CAUSE_CLASSIFICATION == "Natural", ]
head(lightning_ignitions)
nrow(lightning_ignitions) #6100 -- pretty good sample!

acc_ignitions <- short_subset[short_subset$NWCG_CAUSE_CLASSIFICATION == "Human", ]
head(acc_ignitions)
nrow(acc_ignitions) #27232 -- that's a ton!

#-------------------------------------------------------------------------------
# Do a density kernel to estimate intensity
# these are made oversized to avoid edge effects, and then lateraligned and
# clipped to the mask of the study area

lightning_coords <- as.data.frame(st_coordinates(lightning_ignitions))
win <- owin(xrange = range(lightning_coords$X), yrange = range(lightning_coords$Y))
lightning.ppp <- ppp(lightning_coords$X, lightning_coords$Y, window = win)
lightning_raster <- spatstat::density.ppp(lightning.ppp, adjust = 0.2, kernel = "gaussian", eps = 180)
plot(lightning_raster)
hist(lightning_raster)
lightning_raster <- lightning_raster * 1e7
# writeRaster(raster(lightning_raster), "lightning_ignitions.tiff", "GTiff", overwrite = TRUE)

acc_coords <- as.data.frame(st_coordinates(acc_ignitions))
win <- owin(xrange = range(acc_coords$X), yrange = range(acc_coords$Y))
acc.ppp <- ppp(acc_coords$X, acc_coords$Y, window = win)
acc_raster <- spatstat::density.ppp(acc.ppp, adjust = 0.2, kernel = "gaussian", eps = 180)
plot(acc_raster)
hist(acc_raster)
acc_raster <- acc_raster * 1e6
# writeRaster(raster(acc_raster), "acc_ignitions.tiff", "GTiff", overwrite = TRUE)

#clip the new rasters to mask
mask <- raster("./masks_boundaries/mask.tif")
crs(mask) <- "EPSG:2163"

lightning_raster <- raster(lightning_raster)
lightning_clip <- raster::crop(lightning_raster, extent(mask))
lightning_clip <- raster::resample(lightning_raster, mask, method = "bilinear")
lightning_masked <- raster::mask(lightning_clip, mask, maskvalue = 0, updatevalue = 0)
writeRaster(lightning_masked, "./input_rasters_tcsi/lightning_tcsi.tif", "GTiff", overwrite = TRUE)

acc_raster <- raster(acc_raster)
acc_clip <- raster::crop(acc_raster, extent(mask))
acc_clip <- raster::resample(acc_raster, mask, method = "bilinear")
acc_masked <- raster::mask(acc_clip, mask, maskvalue = 0, updatevalue = 0)
writeRaster(acc_masked, "./input_rasters_tcsi/accidental_tcsi.tif", "GTiff", overwrite = TRUE)

