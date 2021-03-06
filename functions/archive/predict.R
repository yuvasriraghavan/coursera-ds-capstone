projectDir = "/Users/smallwes/develop/academic/coursera/datascience/c10-capstone/"
dataDir   <- paste0( projectDir, "data/")
funcDir   <- paste0( projectDir, "functions/")
wkDir <- paste0( projectDir, "")
setwd(wkDir)
#set.seed("4789")

source( paste0(projectDir, "setup.R"))
source( paste0(funcDir, "globalUsePackage.R"))

# PREDICTION FUNCTIONALTIY
source(paste0(funcDir, "doRemoveWords.R"))
source(paste0(funcDir, "doWordStemmer.R"))
source(paste0(funcDir, "getNgramPredictionSet.R"))

# LOAD NGRAM DATAFRAMES
dfGrams1 <- read.csv(paste0( dataDir, "en_US.combined_grams_1.csv" ))
dfGrams2 <- read.csv(paste0( dataDir, "en_US.combined_grams_2.csv" ))
dfGrams3 <- read.csv(paste0( dataDir, "en_US.combined_grams_3.csv" ))
dfGrams4 <- read.csv(paste0( dataDir, "en_US.combined_grams_4.csv" ))
dfGrams5 <- read.csv(paste0( dataDir, "en_US.combined_grams_5.csv" ))

# PREPARE UNI-GRAMS -> GLOBAL SET THAT IS REUSED BETWEEN PREDICTIONS
subGrams1 <- dfGrams1
subGrams1TotalTokensN <- sum(subGrams1$tf)
colnames(subGrams1)[colnames(subGrams1) == 'firstterms'] <- 'token'
subGrams1["type"] <- rep("ngram.1",nrow(subGrams1))
subGrams1["discount"] <- rep(1,nrow(subGrams1))
subGrams1["score"] <-  rep(0.0,nrow(subGrams1))
subGrams1$score <- subGrams1$tf / subGrams1TotalTokensN

# DEBUG SCORING
debugScoring <- function( x, ngram.level, term, base, term.freq, ngram.count, ngram.count.term, discount, score) {
  x <- append(x, paste0(
         "lvl=", ngram.level, " | ",
         "token=", term, " | ", 
         "base=", base, " | ", 
         "tf=", term.freq, " | ", 
         "ngram-1.count=", ngram.count, " | ", 
         "ngram-1.count(",term,")=", ngram.count.term, " | ", 
         "discount=", discount, " | ", 
         "score=", score))
  x
}

# CREATE CLASS WRAPPING A PREDICTION RESULT
setClass("Prediction", slots = list(input = "character", output = "data.frame", debug = "character"))

# FUNC -> DO-PREDICT
doPredict <- function ( sentence ) {
  debug <- c("")
  #print (sentence)
  
  subGrams4 <- getNgramPredictionSet( sentence, 4, dfGrams4, pc )
  subGrams3 <- getNgramPredictionSet( sentence, 3, dfGrams3, pc )
  subGrams2 <- getNgramPredictionSet( sentence, 2, dfGrams2, pc )
  
  # FUNC -> INNER FUNCTION: SCORE MULTIGRAMS ( ngram >= 3 )  (STUPID BACKOFF APPROACH)
  scoreMultiGrams <- function ( ngram.level, gA, gB, backoff.discount, debug ) {
    countB <- sum( gB$tf )
    baseB <- unique( gB$firstterms )
    for (term in gA$lastterm) {
      countBB <- gB[gB$lastterm == term,]$tf
      score <- round((gA[gA$lastterm == term,]$tf / countB) * backoff.discount, 5)
      gA[gA$lastterm == term,]$score = score
      debug <- debugScoring(debug, ngram.level, term, (gA[gA$lastterm == term,]$firstterms), (gA[gA$lastterm == term,]$tf), countB, countBB, backoff.discount, score)
    }
    gA
  }
 
  # FUNC -> SCORE BIGRAMS (STUPID BACKOFF APPROACH)
  scoreBiGrams <- function ( ngram.level, gA, gB, backoff.discount, debug ) {
    for (term in gA$lastterm) {
      countB <- gB[gB$token == term,]$tf
      score <- round((gA[gA$lastterm == term,]$tf / countB) * backoff.discount, 5)  
      gA[gA$lastterm == term,]$score = score
      debug <- debugScoring(debug, ngram.level, term, (gA[gA$lastterm == term,]$firstterms), (gA[gA$lastterm == term,]$tf), countB, countB, backoff.discount, score) 
    }
    gA
  }

  # STUPID BACKOFF SCORING
  scoredGrams5 <- scoreMultiGrams( 5, subGrams4, subGrams4, 1, debug)
  scoredGrams4 <- scoreMultiGrams( 4, subGrams4, subGrams3, 0.4^1, debug)
  scoredGrams3 <- scoreMultiGrams( 3, subGrams3, subGrams2,  0.4^2,debug )
  scoredGrams2 <- scoreBiGrams( 2, head(subGrams2, 50), subGrams1, 0.4^3, debug )
  
  # FUNC -> COMBINE TOKENS
  combineTokens <- function ( ngram.level, combinedScoreTokens, scoredGrams) {
    if ( nrow(scoredGrams) > 0) {
      subScoredGrams <- subset(scoredGrams, select=c("lastterm", "score", "type"))
      colnames(subScoredGrams)[colnames(subScoredGrams) == 'lastterm'] <- 'token'
      #print(paste0("copySet @ ",ngram.level))
      copySet <- setdiff(subScoredGrams$token, combinedScoreTokens$token)
      #print(length(copySet))
      #print(copySet)
      if (length(copySet) > 0) {
        copySetSubScoredGrams <- subScoredGrams[subScoredGrams$token %in% copySet,]
        #print(copySetSubScoredGrams)
        rbind(combinedScoreTokens, copySetSubScoredGrams )
      }
      else { combinedScoreTokens }
    }
    else { combinedScoreTokens }
  }
  
  # COMBINE SCORED TOKENS IN SINGLE DATA.FRAME
  combinedScoreTokens <- data.frame(token=character(), score=numeric(), type=character(), stringsAsFactors=FALSE) 
  combinedScoreTokens <- combineTokens(5, combinedScoreTokens, scoredGrams5)
  combinedScoreTokens <- combineTokens(4, combinedScoreTokens, scoredGrams4)
  combinedScoreTokens <- combineTokens(3, combinedScoreTokens, scoredGrams3)
  combinedScoreTokens <- combineTokens(2, combinedScoreTokens, scoredGrams2)
  
  # ORDER BY SCORE DESC -> HIGHEST TO LOWEST
  output <- head( combinedScoreTokens[with(combinedScoreTokens, order(-score)), ], 5)
  
  # SUBSET NUMBER OF PREDICTIONS TO RETURN
  if (nrow(output) == 0) {
    output <- head(subGrams1, 5)
  }
  
  # RETURN PREDICTION OBJECT
  oPrediction <- new ("Prediction", input = sentence, output = output, debug = debug)
  oPrediction
}
