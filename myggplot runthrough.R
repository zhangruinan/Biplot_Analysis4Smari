# setwd("~/Desktop/OneDrive/MA 386")
# require(openxlsx)
# df <- read.xlsx("DATA_STACKED.XLSX",sheet = 1)
library(HDclassif)   # load data for wine
data(wine)
df = wine

df = df[complete.cases(df),]
df = df[,sapply(df, function(v) var(v, na.rm=TRUE)!=0)]   # remove constant column
df_pca <- prcomp(df,center = TRUE,scale. = TRUE)


library(ggplot2)
library(plyr)
library(scales)
library(grid)

# function parameters
pcobj = df_pca
choices = 1:2
scale = 1
pc.biplot = TRUE 
obs.scale = 1 - scale
var.scale = scale
groups = as.factor(wine$class)
ellipse = TRUE
ellipse.prob = 0.68
labels = NULL
labels.size = 3

var.axes = TRUE 
circle = FALSE
circle.prob = 0.69
varname.size = 3
varname.adjust = 1.5 
varname.abbrev = FALSE

#select_features=c("Q15_26","Q15_28","Q15_1","q7_1","q7_2","q7_3")
select_features=NULL

sample_ratio = 0.5
alpha = 1        # transparency 

# stop condition
stopifnot(length(choices) == 2)

# Recover the SVD
if(inherits(pcobj, 'prcomp')){
  nobs.factor <- sqrt(nrow(pcobj$x) - 1)
  d <- pcobj$sdev
  u <- sweep(pcobj$x, 2, 1 / (d * nobs.factor), FUN = '*')
  v <- pcobj$rotation
} else {
  stop('Expected a object of class prcomp only')
}

# Scores
choices <- c(1,3)
choices <- pmin(choices, ncol(u))

df.u <- as.data.frame(sweep(u[,choices], 2, d[choices]^obs.scale, FUN='*'))

# Directions
v <- sweep(v, 2, d^var.scale, FUN='*')
df.v <- as.data.frame(v[, choices])

# select only desired features
if(typeof(select_features)!=typeof(NULL)){
  df.v <- df.v[select_features,]
}


names(df.u) <- c('xvar', 'yvar')
names(df.v) <- names(df.u)

if(pc.biplot) {
  df.u <- df.u * nobs.factor
}

# Scale the radius of the correlation circle so that it corresponds to 
# a data ellipse for the standardized PC scores
r <- sqrt(qchisq(circle.prob, df = 2)) * prod(colMeans(df.u^2))^(1/4)

# Scale directions
v.scale <- rowSums(v^2)
df.v <- r * df.v / sqrt(max(v.scale))


# Change the labels for the axes
if(obs.scale == 0) {
  u.axis.labs <- paste('standardized PC', choices, sep='')
} else {
  u.axis.labs <- paste('PC', choices, sep='')
}


# Append the proportion of explained variance to the axis labels
u.axis.labs <- paste(u.axis.labs, 
                     sprintf('(%0.1f%% explained var.)', 
                             100 * pcobj$sdev[choices]^2/sum(pcobj$sdev^2)))

# Score Labels
if(!is.null(labels)) {
  df.u$labels <- labels
}

# Grouping variable
if(!is.null(groups)) {
  df.u$groups <- groups
}


# Variable Names
if(varname.abbrev) {
  df.v$varname <- abbreviate(rownames(v))
} else {
  if (length(rownames(v))>length(df.v$varname)){
    if (typeof(select_features)!=typeof(NULL)){
      df.v$varname = select_features
    }else{
      print("get run")
      df.v$varname=rownames(v)
    }
    
  }else{
    df.v$varname <- rownames(v)
  }
}

# Variables for text label placement
df.v$angle <- with(df.v, (180/pi) * atan(yvar / xvar))
df.v$hjust = with(df.v, (1 - varname.adjust * sign(xvar)) / 2)

# set sample ratio
if(sample_ratio<1){
  dat = df.u[sample(nrow(df.u),round(sample_ratio*nrow(df.u))),]
}else{
  dat = df.u
}

# Base plot
g <- ggplot(data = dat, aes(x = xvar, y = yvar)) + 
  xlab(u.axis.labs[1]) + ylab(u.axis.labs[2]) + coord_equal()

if(var.axes) {
  # Draw circle
  if(circle) 
  {
    theta <- c(seq(-pi, pi, length = 50), seq(pi, -pi, length = 50))
    circle <- data.frame(xvar = r * cos(theta), yvar = r * sin(theta))
    g <- g + geom_path(data = circle, color = muted('white'), 
                       size = 1/2, alpha = 1/3)
  }
  
  # Draw directions
  g <- g +
    geom_segment(data = df.v,
                 aes(x = 0, y = 0, xend = xvar, yend = yvar),
                 arrow = arrow(length = unit(1, 'picas')), 
                 color = muted('blue'),size=1)
}

# Label the variable axes
if(var.axes) {
  g <- g + 
    geom_text(data = df.v, 
              aes(label = varname, x = xvar, y = yvar, 
                  angle = angle, hjust = hjust), 
              color = 'darkred', size = varname.size)
}


# Draw either labels or points
if(!is.null(df.u$labels)) {
  
  if(!is.null(df.u$groups)) {
    g <- g + geom_text(aes(label = labels, color = groups), 
                       size = labels.size)
  } else {
    g <- g + geom_text(aes(label = labels), size = labels.size)      
  }
} else {
  if(!is.null(df.u$groups)) {
    
    g <- g + geom_point(aes(color = groups), alpha = alpha)
    
  } else {
    
    g <- g + geom_point(alpha = alpha)      
  }
}


# Overlay a concentration ellipse if there are groups
if(!is.null(df.u$groups) && ellipse) {
  theta <- c(seq(-pi, pi, length = 50), seq(pi, -pi, length = 50))
  circle <- cbind(cos(theta), sin(theta))
  
  ell <- ddply(df.u, 'groups', function(x) {
    if(nrow(x) <= 2) {
      return(NULL)
    }
    sigma <- var(cbind(x$xvar, x$yvar))
    mu <- c(mean(x$xvar), mean(x$yvar))
    
    ed <- sqrt(qchisq(ellipse.prob, df = 2))
    data.frame(sweep(circle %*% chol(sigma) * ed, 2, mu, FUN = '+'), 
               groups = x$groups[1])
  })
  names(ell)[1:2] <- c('xvar', 'yvar')
  
  centroids <- ddply(df.u,"groups",function(x){
    mu <- c(mean(x$xvar), mean(x$yvar))
  })
  
  g <- g+geom_point(data=centroids,aes(x=V1,y=V2,color=groups,shape=groups,size=10))+guides(size=F)
  
  g <- g + geom_path(data = ell, aes(color = groups, group = groups))
}

# Label the variable axes
if(var.axes) {
  g <- g + 
    geom_text(data = df.v, 
              aes(label = varname, x = xvar, y = yvar, 
                  angle = angle, hjust = hjust), 
              color = 'darkred', size = varname.size)
}
# Change the name of the legend for groups
# if(!is.null(groups)) {
#   g <- g + scale_color_brewer(name = deparse(substitute(groups)), 
#                               palette = 'Dark2')
# }

g <- g+theme_bw()

g