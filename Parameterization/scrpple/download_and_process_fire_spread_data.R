library("sf")
library("tidyverse")
library("raster")
library("stars")
library("sp")
library("geoknife")
library("archive")
sf::sf_use_s2(FALSE)

#TODO: add NDVI
#https://zenodo.org/record/4734593
#https://lpdaac.usgs.gov/products/mod13a2v061/
#https://opendap.cr.usgs.gov/opendap/hyrax/MOD13A2.061/contents.html
#TODO: add climate normals
#TODO: add EVI or other fuel proxy
#TODO: corrolate fuels with LANDIS fuel layer
#could use gridmet




setwd("C:/Users/Sam/Documents/Research/TCSI conservation finance/")

template <- raster("./Models/Inputs/masks_boundaries/mask_9311.tif")
raster::values(template) <- 1
sierra_poly <- sf::st_read("./Models/Inputs/masks_boundaries/WIP_Capacity_V1Draft/WIP_Capacity_V1Draft.shp") %>%
  sf::st_zm() %>%
  sf::st_transform(crs(template))
tcsi_poly <- sf::st_read("./Models/Inputs/masks_boundaries/tcsi_area_shapefile/TCSI_v2.shp") %>%
  sf::st_zm() %>%
  sf::st_transform(crs(template))

sierra_poly_wgs <- sierra_poly %>% sf::st_transform(crs = "+proj=longlat +datum=WGS84 +no_defs")

#make a template for the whole sierra
sierra_template <- template
extent(sierra_template) <- extent(sierra_poly)
res(sierra_template) <- res(template)
sierra_template2 <- raster::rasterize(sierra_poly, sierra_template, field = 1)
sierra_template <- sierra_template2
rm(sierra_template2)

daily_perims_all <- sf::st_read("./Parameterization/calibration data/geomac_all_years/perims_2000_2021.shp") %>%
  sf::st_transform(crs = sf::st_crs(sierra_poly)) %>%
  sf::st_intersection(sierra_poly) %>%
  dplyr::filter(fireyear >= 2000) %>%
  mutate(incidentna = paste0(incidentna, fireyear))

#recalculate area -- the gisacres column is a crazy mess, no idea what happened there
area <- map(sf::st_geometry(daily_perims_all), ~ sf::st_area(.)) %>%
  unlist() %>%
  `/`(4046.86) #convert to acres

# plot(area ~ daily_perims_all$gisacres,
#   xlim = c(0, 4e+05))

daily_perims_all$gisacres <- area



#fix dates
library("lubridate")
daily_perims_all$perimeterd
normal_format <- which((substr(daily_perims_all$perimeterd, 1, 4) %in% c(2000:2022)))
different_format <- which(!(substr(daily_perims_all$perimeterd, 1, 4) %in% c(2000:2022)))

dates_with_time <- mdy_hms(daily_perims_all[different_format, ]$perimeterd)
dates_mdy <- mdy(daily_perims_all[different_format, ]$perimeterd)

dates_fixed <- ifelse(!is.na(dates_with_time), 
                      as.character(dates_with_time, format = "%Y-%m-%d"), 
                      as.character(dates_mdy, format = "%Y-%m-%d"))

daily_perims_all[different_format, ]$perimeterd <- dates_fixed

daily_perims_all$perimeterd <- as.Date(daily_perims_all$perimeterd, format = "%Y-%m-%d")

#remove duplicates (polygons with same size on same day for same fire)
daily_perims_all <- daily_perims_all %>%
  group_by(incidentna) %>%
  group_by(perimeterd) %>%
  slice_max(gisacres) %>%
  distinct(gisacres, .keep_all= TRUE) %>%
  filter(fireyear %in% c(2000:2021))


#explore data
#396 fires with more than 10 daily perimeters!
# reduced to 139 after removing duplicates :(
length(table(daily_perims_all$incidentna)[table(daily_perims_all$incidentna) > 2])

# test <- daily_perims_all %>% 
#   group_by(incidentna) %>%
#   slice_max(gisacres) %>%
#   group_by(fireyear) %>%
#   summarise(area_burned = sum(gisacres), .groups = "keep")
# 
# plot(test$area_burned ~ test$fireyear)

##write example data for figure



# 
# test2 <- daily_perims_all %>%
#   group_by(incidentna) %>%
#   slice_max(gisacres)
# 
# plot(st_geometry(test2))
# test2 <- st_cast(test2, to = "MULTIPOLYGON")
# write_sf(test2, "fires for daily perimeters.shp")
#-------------------------------------------------------------------------------
# Import slope and aspect from DEM
#-------------------------------------------------------------------------------
# these rasters in the wrong CRS, but it takes a  ton of RAM to reproject them.
# Instead, I'll project the fire boundary to match, and then crop and reproject.
# It's actually really  fast to do it this way.

slope_full <- read_stars("./Parameterization/calibration data/topography/sierra_slope.tif") %>%
  stars::st_warp(dest = stars::st_as_stars(sierra_template))

aspect_full <- read_stars("./Parameterization/calibration data/topography/sierra_aspect.tif") %>%
  stars::st_warp(dest = stars::st_as_stars(sierra_template))

#-------------------------------------------------------------------------------
#LANDFIRE layers
#-------------------------------------------------------------------------------
# layers of fine fuels and ladder fuels, see create_fine_and_ladder_fuels_from_landfire_whole_sierra.R
# fuels include fires that happened that year, so, e.g., 2001 fires cannot use 2001 fuels
landfire_2001_fine <- read_stars("D:/Data/Landfire fuels/sierra/landfire_fine_2001.tif") %>%
  stars::st_warp(dest = stars::st_as_stars(sierra_template))
landfire_2012_fine <- read_stars("D:/Data/Landfire fuels/sierra/landfire_fine_2012.tif")%>%
  stars::st_warp(dest = stars::st_as_stars(sierra_template))
landfire_2014_fine <- read_stars("D:/Data/Landfire fuels/sierra/landfire_fine_2014.tif")%>%
  stars::st_warp(dest = stars::st_as_stars(sierra_template))
landfire_2019_fine <- read_stars("D:/Data/Landfire fuels/sierra/landfire_fine_2019.tif")%>%
  stars::st_warp(dest = stars::st_as_stars(sierra_template))
landfire_2020_fine <- read_stars("D:/Data/Landfire fuels/sierra/landfire_fine_2020.tif")%>%
  stars::st_warp(dest = stars::st_as_stars(sierra_template))
landfire_2021_fine <- read_stars("D:/Data/Landfire fuels/sierra/landfire_fine_2021.tif")%>%
  stars::st_warp(dest = stars::st_as_stars(sierra_template))

#-----------------------------------------------------------------------------------
# MTBS severity mosaics
#-------------------------------------------------------------------------------
#used for combustion buoyancy. We'll import them one year at a time as needed
mtbs_folder <- "D:/Data/mtbs_mosaic/mtbs_mosaic/composite_data/MTBS_BSmosaics"
mtbs_list <- list.files(mtbs_folder, pattern = "*.tif", recursive = TRUE, full.names = TRUE)
# mtbs_stack <- stack(mtbs_list)

#-------------------------------------------------------------------------------
# Function to download windspeed data
#-------------------------------------------------------------------------------
download_windspeed <- function(boundary){  
  # 
  # boundary <- daily_perims_all %>% 
  #   filter(incidentna == fire_name &
  #            perimeterd == perimeterd_input)
  # 
  #shapefile for fire
  
  if(nrow(boundary) > 1) boundary <- boundary[1, ] #take the first entry if there are duplicates
  
  fire_boundary <- boundary %>%
    sf::st_transform(crs = "+proj=longlat +datum=WGS84") #reproject to CRS that geoknife needs
  
  year <- fire_boundary$fireyear
  fire_date <- fire_boundary$perimeterd
  
  print(year)
  print(fire_date)
  
  #"stencil" is what geoknife uses for the extent of the data
  #
  stencil <- fire_boundary %>%
    sf::st_bbox() %>%
    sf::st_as_sfc() %>%
    as("Spatial") %>%
    simplegeom()
  
  vars_url <- c("vs", "th")
  
  urls <- paste0("http://thredds.northwestknowledge.net:8080/thredds/dodsC/MET/",vars_url,"/", vars_url, "_", year, ".nc")
  
  
  vars_long <- c("wind_speed", 
                 "wind_from_direction")
  
  
  knife <- webprocess(wait = TRUE)
  # query(knife, 'algorithms')
  
  # area grid statistics are the default, but we can change it if we  (we don't)
  algorithm(knife) <- list('OPeNDAP Subset' = 
                             "gov.usgs.cida.gdp.wps.algorithm.FeatureCoverageOPeNDAPIntersectionAlgorithm")
  
  
  layers <- list()
  
  for(i in 1:2){
    
    #set the fabric for a new variable, but keep everything else the same (i.e. the stencil and knife)
    fabric <- webdata(url = urls[i], times = c(as.POSIXct(boundary$perimeterd), as.POSIXct(boundary$perimeterd)))
    variables(fabric) <- vars_long[i]
    print(vars_long[i])
    
    job <- geoknife(stencil, fabric, knife, wait = TRUE, OUTPUT_TYPE = "geotiff")
    
    # file <- geoknife::download(job, destination = paste0("./Parameterization/calibration data/climate/downloaded/", vars_url[i],'/temp.zip'), overwrite=TRUE)
    
    # newdir <- paste0("./Parameterization/calibration data/climate/downloaded/",vars_url[i], "/",
    #                            boundary$incidentna, boundary$perimeterd)
    
    dest <- file.path(tempdir(), paste0(vars_long[i], '_data.zip'))
    file <- download(job, destination = dest, overwrite = TRUE)
    tiff.dir <- file.path(tempdir(), vars_long[i])
    #delete contents from previous fire
    unlink(tiff.dir, recursive = TRUE)
    
    archive::archive_extract(archive = file, dir = tiff.dir)
    
    #this is a weird file; stars doesn't like it. The metadata is all messed up. raster still works okay though!
    layers[i] <- raster(list.files(file.path(tempdir(), vars_long[i]), full.names = TRUE))
    # print(boundary$incidentna)
    # print(boundary$perimeterd)
    # print(newdir)
  }
  
  
  return(c(layers))
}

#*******************************************************************************
# Extract fire spread information
#*******************************************************************************

# initialize dataframe to catch the data
# we just need to know the date and cell location,
# and then we can do another loop to extract the fwi, fuels, and windspeed

spread_data <- data.frame(fire_name = character(1000000),
                               year = numeric(1000000),
                               day = numeric(1000000),
                               cell = numeric(1000000),
                               success = logical(1000000),
                               days_between = numeric(1000000)
                               )

years <- 2000:2021

# this little guy keeps track of what row we're on, and gets incremented
# as data gets added to the dataframe, so we can avoid recursively binding rows
rowtracker <- 1

error_flag <- FALSE
#-------------------------------------------------------------------------------
# nested loop goes through each year, finds fires in that year,
# then loops through fires, then through days per fire. 
# The loop extracts the identity of potential fire cells and whether or not 
# fire spread successfully to those cells


for(k in 1:length(years)){
  year <- years[k]
  
  message("Processing fire spread for year ", year)

  daily_perims <- daily_perims_all %>%
    filter(fireyear == year)
  
  # TODO find potential fires
  # look through years and extract fires which lasted a certain # days, or spread to a certain size?
  fires_current_year <- daily_perims %>%
    dplyr::group_by(incidentna) %>%
    dplyr::summarise(incidentna = dplyr::first(incidentna),
                     n_days = n_distinct(perimeterd),
                     max_size = max(gisacres)) %>%
    filter(n_days >= 2)
  
  if(nrow(fires_current_year) == 0){
    message(paste0("No fires that lasted 2 or more days in year ", year))
    next()
  }

  for(fire in fires_current_year$incidentna){
    
    current_fire <- tryCatch(
      {
        daily_perims[daily_perims$incidentna == fire, ] %>%
        arrange(perimeterd) %>%
        group_by(perimeterd) %>%
        slice_max(gisacres) %>%
        distinct(gisacres, .keep_all = TRUE) %>% #in case there's duplicate polygons with the same gisacres and date
        ungroup() %>%
        mutate(spread = gisacres - dplyr::lag(gisacres, default = NA),
               days_between = dplyr::lead(perimeterd, default = NA) - perimeterd) %>% #TODO fix how "days_between" is calculated?
        sf::st_cast("MULTIPOLYGON")
      },
      error=function(cond) {
        
        message(paste("Error processing fire", fire))
        message("Here's the original error message:")
        message(cond)
        error_flag <<- TRUE
        
      }
    )
    if(error_flag) next()
    
    # print(fire)
    # plot(st_geometry(current_fire))
    # plot(current_fire$gisacres ~ as.Date(current_fire$perimeterd))
    # plot(current_fire$spread ~ as.Date(current_fire$perimeterd)) #all spread is > 0
    
    if(sum(current_fire$days_between == 1, na.rm = TRUE) < 1){
      message("Skipping fire due to lack of successive daily perimeters")
      next()
    }
    
    #if fire decreases in size, use previous fire polygon
    for(i in 2:nrow(current_fire)){
      if(!is.na(current_fire$spread[i]) & current_fire$spread[i] < 0){
        sf::st_geometry(current_fire)[i] <-  sf::st_geometry(current_fire[i-1, ])
      }
    }
    
    #if data looks good, then do the loop to get potential/burned cells
    for(i in 1:length(unique(current_fire$perimeterd))){
      print(i)
      #TODO check if data for burn day
      #if day is burning
      if(i == 1){
        burning <- raster::mask(sierra_template, current_fire[i, ], updatevalue = NA) # 1 means "burning"
        burned <- burning
        # plot(burning, ext = st_bbox(current_fire), main = paste("Burned on Day ", i))
        # writeRaster(burning, paste0("burning_day", i, ".tif"), overwrite = TRUE)
      }else{
        # cells within the polygon this timestep, minus the ones that were burned as of
        # the previous timestep
        burning <- raster::mask(sierra_template, current_fire[i, ], updatevalue = NA) %>%
          mask(previous_burned, inverse = TRUE) #burned from last timestep
        # plot(burning, ext = st_bbox(current_fire), main = paste("Burned on Day ", i))
        # writeRaster(burning, paste0("burning_day", i, ".tif"), overwrite = TRUE)
        
        burned <- raster::mask(sierra_template, current_fire[i, ], updatevalue = NA)
        
        
        #for the potential cells added last timestep, which ones ended up burning this timestep?
        # previous-year's first_row and last_row
        spread_data$success[first_row:last_row] <- ifelse(spread_data$cell[first_row:last_row] %in% which(raster::values(burning) == 1),
                                                               TRUE,
                                                               FALSE)
      }
      
      #calculate potential burn based on currently burning cells
      potential_burn <- adjacent(burning, cells = which(raster::values(burning) == 1),
                                 directions = 4, pairs = FALSE, include = FALSE) %>%
        `[`(!(. %in% which(raster::values(burned) == 1))) #remove cells that already burned
      potential_burn_map <- burning %>% setValues(0)
      potential_burn_map[potential_burn] <- 1
      # plot(potential_burn_map, ext = st_bbox(current_fire), 
      #      main = paste0("Potential to burn on Day", i+1))
      # writeRaster(potential_burn_map, paste0("potential_burn_day", i+1, ".tif"), overwrite = TRUE)
      
      previous_burned <- burned #update for next timestep
      
      n_potential <- length(potential_burn)
      if(n_potential == 0) next()
      
      print(rowtracker)
      
      first_row <- rowtracker
      last_row <- first_row + n_potential -1
      rowtracker <- last_row + 1
      
      #add daily fire data to dataframe
      spread_data$fire_name[first_row:last_row] <- current_fire$incidentna[i]
      spread_data$year[first_row:last_row] <- current_fire$fireyear[i]
      spread_data$day[first_row:last_row] <- format(as.Date(current_fire$perimeterd[i]), "%j")
      spread_data$cell[first_row:last_row] <- potential_burn
      spread_data$success[first_row:last_row] <- F
      spread_data$days_between[first_row:last_row] <- current_fire$days_between[i]
      
      #the loop ends on the last day of the fire, so spread success is left as FALSE,
      # and days_between should be NA for the last fire polygon (as it's only used
      # to evaluate the previous fire, not generate its own potential fire spread)
    }
      
  }
 
} 

spread_data  <- spread_data %>% 
  dplyr::filter(!is.na(fire_name)) %>%
  dplyr::filter(fire_name != "")



#*******************************************************************************
# extract climate, topography, and fuel variables for each cell
#*******************************************************************************

backup <- spread_data
spread_data$day <- as.integer(spread_data$day)
spread_data$year <- as.integer(spread_data$year)

#extract topography
#holy cow stars is so fast
spread_data$slope <- slope_full[[1]][spread_data$cell]
spread_data$aspect <- aspect_full[[1]][spread_data$cell]

#extract fuels for each cell, from the proper fuel layer
spread_data$fuel <- NA

for(i in 1:20){
  #TODO clean this up; this is horrible style. It's still fast though, somehow!
  year <- c(2002:2021)[i]
  if(year %in% c(2002:2012)){
    #no LANDFIRE data for 2000
    spread_data[spread_data$year == year, "fuel"] <- landfire_2001_fine[[1]][spread_data[spread_data$year == year, "cell"]]
  } else if(year %in% c(2013:2014)){
    spread_data[spread_data$year == year, "fuel"] <- landfire_2012_fine[[1]][spread_data[spread_data$year == year, "cell"]]
  } else if(year %in% c(2015:2019)){
    spread_data[spread_data$year == year, "fuel"] <- landfire_2014_fine[[1]][spread_data[spread_data$year == year, "cell"]]
  }else if(year %in% c(2020)){
    spread_data[spread_data$year == year, "fuel"] <- landfire_2019_fine[[1]][spread_data[spread_data$year == year, "cell"]]
  }else if(year %in% c(2021)){
    spread_data[spread_data$year == year, "fuel"] <- landfire_2020_fine[[1]][spread_data[spread_data$year == year, "cell"]]
  }
}


#loop through fires to extract FWI, wind speed, wind direction

#download FWI
spread_data$year_days <- paste0(spread_data$year, spread_data$day)
unique_year_days <- unique(spread_data$year_days)

for(yearday in unique_year_days){
  
  error_flag <- FALSE
  
  fwi_date <- format(as.Date(paste(yearday), format = "%Y%j"),
                 format = "%Y%m%d")
  fwi_year <- as.numeric(substr(yearday, 1, 4))
  fwi_day <- as.numeric(substr(yearday, 5, 7))
  tail <- paste0(fwi_date, ".nc")
  file <- paste0("FWI.MERRA2.CORRECTED.Daily.Default.", tail)
  
  print(paste("Year = ", fwi_year))
  print(paste("Day = ", fwi_day))
  
  day_data <- spread_data %>% dplyr::filter(year_days == yearday)
  
  #create a directory if needed
  if(!(paste0("./parameterization/calibration data/fwi/", fwi_year) %in% 
       list.dirs("./parameterization/calibration data/fwi"))){
    dir.create(paste0("./parameterization/calibration data/fwi/", fwi_year))
  }
  
  #check if we've already got that raster, otherwise download it
  if(paste0("./parameterization/calibration data/fwi/", fwi_year) %in% 
     list.dirs("./parameterization/calibration data/fwi")){
    message("FWI data already downloaded. Loading from disk.")
  } else{
    #download FWI raster, ~16 mb
    tryCatch(
      {
        download.file(url = paste0("https://portal.nccs.nasa.gov/datashare/GlobalFWI/v2.0/fwiCalcs.MERRA2/Default/MERRA2.CORRECTED/",fwi_year,"/",file), 
                      destfile = paste0("./parameterization/calibration data/fwi/", fwi_year,"/", tail), method = "curl", quiet = FALSE,
                      cacheOK = TRUE)
      },
      error=function(cond) {
        
        message(paste("Error downloading climate data for ", fwi_date))
        message("Here's the original error message:")
        message(cond)
        error_flag <<- TRUE
        
      }
    )
  }
  
  if(error_flag) next()
  
  # TODO figure out how to suppress messages on loading
  fwi <- tryCatch(
    {stars::read_stars(paste0("./parameterization/calibration data/fwi/", fwi_year,"/", tail)) %>%
    dplyr::select("MERRA2.CORRECTED_FWI") %>%
    sf::st_set_crs(st_crs(sierra_poly_wgs)) %>%
    `[`(sierra_poly_wgs) %>%
    stars::st_warp(crs = st_crs(sierra_poly)) %>%
    stars::st_warp(dest = stars::st_as_stars(sierra_template))
    }, 
    error=function(cond) {
      
      message(paste("Error downloading process FWI data for ", fwi_date))
      message("Here's the original error message:")
      message(cond)
      error_flag <<- TRUE
      
    }
  )
  if(error_flag) next() 
  
  fwi_vals <- fwi[[1]][day_data$cell]
  
  spread_data[spread_data$year_days == yearday, "fwi"] <- fwi_vals
  
}

spread_data_back2 <- spread_data

#-------------------------------------------------------------------------------
# Get wind speed and wind direction
#-------------------------------------------------------------------------------

for(fire_name_ws in unique(spread_data$fire_name)){
  error_flag <- FALSE
  
  current_fire <- spread_data %>%
    dplyr::filter(fire_name == fire_name_ws)
  
  for(yearday in unique(current_fire$year_days)){
    yearday <- as.character(yearday)
    
    current_fire_day <- current_fire %>%
      filter(year_days == yearday)
    boundary <- daily_perims_all %>%
      dplyr::filter(incidentna == fire_name_ws,
                    perimeterd == as.Date(yearday, format = "%Y%j"))
    print(as.Date(yearday, format = "%Y%j"))
    boundary$perimeterd <- as.Date(boundary$perimeterd) #needed for geoknife
    
    
    #download and process the wind data
    wind_data <- tryCatch(
      {
      download_windspeed(boundary) #TODO fix this!! We can get multiple days in one go!
    }, 
    error = function(cond) {
      message(paste("Error downloading wind data data for ", fwi_date))
      message("Here's the original error message:")
      message(cond)
      error_flag <<- TRUE
      }
    )
    if(error_flag) next() 
    
    
    #project and wrangle data
    windspeed <- wind_data[[1]] %>%
      raster::projectRaster(. , sierra_template)
    winddirection <- wind_data[[2]] %>%
      raster::projectRaster(., sierra_template, method = "ngb")
    
    #extract wind data for the cells we're interested in
    spread_data[spread_data$fire_name == fire_name_ws & spread_data$year_days == yearday, "windspeed"] <- 
      windspeed[current_fire_day$cell]
    spread_data[spread_data$fire_name == fire_name_ws & spread_data$year_days == yearday, "winddirection"] <- 
      winddirection[current_fire_day$cell]
  }
  
}


backup <- spread_data
#-------------------------------------------------------------------------------
# Extract upwind fire severity
#-------------------------------------------------------------------------------

#find what cell is upwind of the potential fire cell
rose_breaks <- c(0, 45, 135, 225, 315, 360)
rose_labs <- c(
  "North", "East", "South", "West", "North"
)

spread_data <- spread_data %>%
  mutate(
    rose = cut(
      winddirection,
      breaks = rose_breaks,
      labels = rose_labs,
      right = FALSE,
      include.lowest = TRUE
    )
  )
    
#find which cell is upwind of each cell
rowcols <- rowColFromCell(sierra_template, spread_data$cell)
rowcol_new <- rowcols

rowcol_new[, 1] <- rowcols[, 1] + ifelse(spread_data$rose =="North",
                                            -1,
                                            ifelse(spread_data$rose =="South",
                                                   1, 0))
rowcol_new[, 2] <- rowcols[, 2] + ifelse(spread_data$rose =="East",
                                         -1,
                                         ifelse(spread_data$rose == "West",
                                                1, 0))

spread_data$cell_mtbs <- cellFromRowCol(sierra_template, rowcol_new[, 1], rowcol_new[, 2])

mtbs_mosaics <- mtbs_list[17:37]

sierra_poly_mtbs <- sierra_poly %>% 
  sf::st_transform(crs = "ESRI:102039")

#make a big stars list of mtbs rasters as stars proxies
#mtbs rasters are in ESRI:102039 or EPSG:42303
# mtbs_stack <- mtbs_mosaics %>%
#   map(~stars::read_stars(.x = .)) %>%
#   map(~sf::st_set_crs(x = ., value = "ESRI:102039")) %>%
#   map(~sf::st_crop(x = ., y = sierra_poly_mtbs)) %>%
#   map(~stars::st_warp())

# assign a potential fire cell a value based on the severity of its upwind cell
# loop over years with fire spread data
for(year in unique(spread_data$year)){
  mtbs_year <- raster(mtbs_mosaics[year - 1999]) %>%
    raster::crop(x = ., y = sierra_poly_mtbs) %>%
    raster::projectRaster(from = ., to = sierra_template, method = "ngb")
  
  plot(mtbs_year)
  
    spread_data[spread_data$year == year, "fire_severity"] <- tryCatch( {
      
      mtbs_year[spread_data[spread_data$year == year, "cell_mtbs"]]
      
    }, error = function(cond){
      
      message(paste("Error extractng MTBS for ", year))
      message("Here's the original error message:")
      message(cond)
      error_flag <<- TRUE
      
    }
    )
}


#-------------------------------------------------------------------------------
# Calculate effective windspeed
#-------------------------------------------------------------------------------

#MTBS severity goes 0 = masked out; 1 = low intensity or unburned; 2 = low; 3 = moderate severity; 4 = high
#; 5 = increased greenness, 6 = non-processing mask

# This changes based on fire severity. Combustion buoyancy.
#severity of 4 = 50; severity of 3 = 25; severity of 2 = 10; severity of 1 = 5; unburned or increased greenness =5

U_b_lookup <- data.frame(code = c(0:6),
                         U_b = c(5, 5, 10, 25, 50, 5, 5))


spread_data$U_b <- ifelse(is.na(spread_data$fire_severity), 5,
              U_b_lookup[match(spread_data$fire_severity, U_b_lookup$code), "U_b"])

### Calculating windspeed in direction of spread 
spread_data$relative_wd <- spread_data$winddirection - spread_data$aspect

#Calculate Ua_Ub, incorporating the combustion buoyancy
spread_data$Ua_Ub <- spread_data$windspeed / spread_data$U_b

### Calculating effective wind speed. 
# gotta convert everything from degrees to radians also
spread_data <- spread_data %>%
  mutate(eff_wspd = 
           U_b * ((Ua_Ub^2) + 2*(Ua_Ub) * sin(slope * (pi/180)) * cos(relative_wd * (pi/180)) + sin(slope * (pi/180))^2)^0.5
  )
                  


#relativize fuels
max_fuel <- 1000
spread_data$fuel <- ifelse(spread_data$fuel < max_fuel, 
                           spread_data$fuel / max_fuel,
                           1)


#------------------------------------------------------
# get NDVI

#START HERE
spread_data <- read.csv("./Parameterization/calibration data/processed_fire_spread_data_new_days_between.csv")

modis_list <- list.files("D:/Data/modis/downloaded_appEARS", full.names = TRUE)
modis_rasters <- data.frame(file = modis_list[grep("NDVI", modis_list)])

modis_rasters$date <- str_match(modis_rasters$file, "(?:_doy)(\\d+)")[, 2] %>%
  as.Date("%Y%j")

get_ndvi_before <- function(firename){
  
  first_date <- spread_data %>% 
    filter(fire_name == firename) %>% 
    summarise(min(year_days)) 
  first_date <- as.Date(as.character(first_date$`min(year_days)`), format = "%Y%j")
  
  year <- substr(first_date, 1, 4)
  
  modis_rasters$distance_ig <- (first_date - modis_rasters$date) 
  modis_file <- modis_rasters[which.min(modis_rasters[modis_rasters$distance_ig>0, "distance_ig"]), "file"]
  
  modis_before <- stars::read_stars(modis_file) %>%
    stars::st_warp(dest = stars::st_as_stars(sierra_template))
  
  modis_vals <- modis_before[[1]][spread_data[spread_data$year == year & spread_data$fire_name == firename,
                           "cell"]]
  
  return(modis_vals)
}

for(fire_name_modis in unique(spread_data$fire_name)){
  message(fire_name_modis)
  spread_data[spread_data$fire_name == fire_name_modis,"ndvi"] <- get_ndvi_before(fire_name_modis)
}


write.csv(spread_data, "./Parameterization/calibration data/processed_fire_spread_data_new_days_between_2023-8-8.csv")
