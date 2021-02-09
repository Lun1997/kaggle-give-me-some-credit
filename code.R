# 讀取參數====
args = commandArgs(trailingOnly=TRUE)
if (length(args)==0) {
  stop("USAGE: Rscript hw5_studentID.R --fold n --train Titanic_Data/train.csv --test Titanic_Data/test.csv --report performance.csv --predict predict.csv", call.=FALSE)
}

#輸入參數(測試)====
args[1]="--fold"
args[2]=5
args[3]="--train"
args[4]="Data/training.csv"
args[5]="--test"
args[6]="Data/test.csv"
args[7]="--report"
args[8]="performance1.csv"
args[9]="--predict"
args[10]="predict.csv"

# 解析參數&指派====
i<-1 
while(i < length(args)){
  if(args[i] == "--fold"){ 
    kfold=as.numeric(args[i+1])
    i<-i+1
  }
  else if(args[i] == "--train"){
    trainfile=args[i+1]
    i<-i+1
  }
  else if(args[i] == "--test"){
    testfile=args[i+1]
    i<-i+1
  }
  else if(args[i] == "--report"){
    performancefile=args[i+1]
    i<-i+1
  }
  else if(args[i] == "--predict"){
    predictfile=args[i+1]
    i<-i+1
  }
  else{
    stop(paste("Unknown flag", args[i]), call.=FALSE)
  }
  i<-i+1
}
print("================= prarmeters detail =================")

print(args)

print("================= Variable assignment =================")
paste("kfold =",kfold)
paste("trainfile =",trainfile)
paste("testfile =",testfile)
paste("performancefile =",performancefile)
paste("predictfile =",predictfile)

#print("============ This R script takes some time to execute ============")



#前處理==================

#1.package====

if(!require("xgboost")){install.packages("xgboost")}
library(xgboost)
if(!require("ROCR")){install.packages("ROCR")}
library(ROCR)

#2.data====

#read
train=read.csv(trainfile,header=T)
test=read.csv(testfile,header=T)

#clean
train=train[,-1]
test=test[,-1]


#NA

# na=function(x){
#   x[which(is.na(x))]=""
#   return(sum(x==""))
# }
# natrain=sum(is.na(train))
# natest=sum(is.na(test))
# natrain
# natest

#factor

# train$SeriousDlqin2yrs=as.factor(as.character(train$SeriousDlqin2yrs))





#3.fold====

index=sample(cut(x=1:nrow(train),breaks=kfold,labels=FALSE))
FOLD=list()
for(i in 1:kfold){
  
  foldlsit=list()
  
  if(i < kfold){
    foldlsit[[1]]=subset(train,index==i)  #test
    foldlsit[[2]]=subset(train,index==i+1)#validation
    foldlsit[[3]]=subset(train,index!=i&index!=i+1)#train
  }
  else{
    foldlsit[[1]]=subset(train,index==i)  #test
    foldlsit[[2]]=subset(train,index==1)#validation
    foldlsit[[3]]=subset(train,index!=i&index!=1)#train
  }
  names(foldlsit)=c("tset","validation","train")
  FOLD[[i]]=foldlsit
}
names(FOLD)=paste("fold",1:kfold)


#k-fold CV====

performance=matrix(NA,kfold+1,4)
colnames(performance)=c("set","training","validation","test")
performance[,1]=c(names(FOLD),"ave.")

#xgboost 參數設定
xgb.params = list(
  colsample_bytree = 0.5,                    
  subsample = 0.5,                      
  booster = "gbtree",
  max_depth = 5,           
  eta = 0.03,
  objective = "binary:logistic",
  gamma = 0
) 
#執行
p=proc.time()
for(f in 1:kfold){
  
  Test=FOLD[[f]][[1]]
  dTest=xgb.DMatrix(data=as.matrix(Test[,2:11]),label=Test$SeriousDlqin2yrs)
  
  validation=FOLD[[f]][[2]]
  dvalidation=xgb.DMatrix(data=as.matrix(validation[,2:11]),label=validation$SeriousDlqin2yrs)
  
  Train=FOLD[[f]][[3]]
  dTrain=xgb.DMatrix(data=as.matrix(Train[,2:11]),label=Train$SeriousDlqin2yrs)
  
  TV=rbind(Train,validation)
  dTV=xgb.DMatrix(data=as.matrix(TV[,2:11]),label=TV$SeriousDlqin2yrs)
  
  
  #xgboost
  
  #1.ntree
  cv.model= xgb.cv(
    params = xgb.params, 
    data = dTV,
    nfold = 5,     
    nrounds=100,   
    early_stopping_rounds = 30, 
    print_every_n = 100 
  ) 
  best.nrounds = cv.model$best_iteration 
  
  #2.model
  
  bestmodel = xgboost(data=dTV,params=xgb.params,nrounds=best.nrounds,
                      print_every_n = 100)
  
  
  #3.performance
  
  prob_Train = predict(bestmodel,dTrain)
  list_Train = list(predictions = prob_Train, labels = Train$SeriousDlqin2yrs)
  pred_Train = prediction(list_Train$predictions, list_Train$labels)
  auc1 = performance(pred_Train,'auc')
  p1 = auc1@y.values[[1]];p1=round(p1,2)
  
  prob_validation = predict(bestmodel,dvalidation)
  list_validation = list(predictions = prob_validation, labels = validation$SeriousDlqin2yrs)
  pred_validation = prediction(list_validation$predictions, list_validation$labels)
  auc2 = performance(pred_validation,'auc')
  p2 = auc2@y.values[[1]];p2=round(p2,2)
  
  prob_Test = predict(bestmodel,dTest)
  list_Test = list(predictions = prob_Test, labels = Test$SeriousDlqin2yrs)
  pred_Test = prediction(list_Test$predictions, list_Test$labels)
  auc3 = performance(pred_Test,'auc')
  p3 = auc3@y.values[[1]];p3=round(p3,2)
  
  performance[f,2:4]=c(p1,p2,p3)
}


perf=performance[1:kfold,2:4]
perf=apply(perf,2,as.numeric)
performance[kfold+1,2:4]=round(apply(perf,2,mean),2)
performance

proc.time()-p


#predict

dtrain=xgb.DMatrix(data=as.matrix(train[,2:11]),label=train$SeriousDlqin2yrs)
dtest=xgb.DMatrix(data=as.matrix(test[,2:11]),label=test$SeriousDlqin2yrs)

xgb.params2=list(
  colsample_bytree = 0.5,                    
  subsample = 0.5,                      
  booster = "gbtree",
  max_depth = 5,           
  eta = 0.03,
  objective = "binary:logistic",
  gamma = 0
) 
cv.Model= xgb.cv(
  params = xgb.params2, 
  data = dtrain,
  nfold = 10,     
  nrounds=200,   
  early_stopping_rounds = 50, 
  print_every_n = 200 
) 
Best.nrounds = cv.Model$best_iteration 
Model = xgboost(data=dtrain,params=xgb.params2,nrounds=Best.nrounds,print_every_n = 100)
final_predict = predict(Model,dtest)
final_predict = data.frame( Id = 1:101503 , Probability = final_predict )

#write
write.csv(performance,file=performancefile,quote=F,row.names=F)
write.csv(final_predict,file=predictfile,quote=F,row.names=F)

