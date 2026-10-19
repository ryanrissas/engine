import sys, json, pickle, numpy as np, warnings, math; warnings.filterwarnings('ignore')
sys.argv=[sys.argv[0], '/dev/null']
src=open('sa_train.py').read()
exec(src.split("Xs, ys, gs = []")[0].replace("data = json.load(open(SRC))",""))
d=pickle.load(open('sa_model.pkl','rb')); m=d['model']; prior=d['prior']; T=d['T']
N=240; S=N*30
def hr(i): return 55+8*math.sin(i/600)+3*math.sin(i/37)+(15 if 3000<=i<3300 else 0)
def ang(i): return 10*math.sin(i/900)+(30*math.sin(i) if i%997<20 else 0)
labels=[[i*30,0] for i in range(N)]
H=[[i,hr(i)] for i in range(S)]
A=[]
for i in range(S):
    if 5000<=i<5060: continue   # a minute with no gravity
    a=math.radians(ang(i)); A.append([i, math.cos(a), 0.0, math.sin(a)])
X,_=night_features(labels,H,A); X=np.nan_to_num(X,nan=0.0)
P=m.predict_proba(X)
def vit(P,a=0.5):
    L=np.log(np.clip(P,1e-9,None))-a*np.log(prior); lT=np.log(T); n=len(L)
    D=np.zeros((n,4)); B=np.zeros((n,4),int); D[0]=L[0]+np.log(prior)
    for i in range(1,n):
        s=D[i-1][:,None]+lT; B[i]=s.argmax(0); D[i]=s.max(0)+L[i]
    p=np.zeros(n,int); p[-1]=D[-1].argmax()
    for i in range(n-1,0,-1): p[i-1]=B[i,p[i]]
    return p
path=vit(P)
json.dump({'features':X.tolist(),'probs':P.tolist(),'path':path.tolist()},open('/home/claude/engine/test/fixtures/sleep_stage_model_parity.json','w'))
print(np.bincount(path,minlength=4))
