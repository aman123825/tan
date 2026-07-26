from __future__ import annotations
from dataclasses import dataclass,field
from statistics import mean
from typing import Literal

@dataclass
class Staircase:
    value:float;minimum:float;maximum:float;step:float
    harder:Literal['down','up']='down';rule_correct:int=2;stop_reversals:int=8
    step_factor:float=1.0;step_reduction_reversals:int=0;min_step:float|None=None
    consecutive:int=0;last_direction:int=0;reversals:list[float]=field(default_factory=list);trials:int=0
    current_step:float=field(init=False,default=0.0)
    def __post_init__(self):
        if self.min_step is None:self.min_step=self.step
        self.current_step=self.step
    def submit(self,correct:bool):
        self.trials+=1;direction=0
        if correct:
            self.consecutive+=1
            if self.consecutive>=self.rule_correct:direction=-1 if self.harder=='down' else 1;self.consecutive=0
        else:
            self.consecutive=0;direction=1 if self.harder=='down' else -1
        if direction:
            if self.last_direction and direction!=self.last_direction:
                self.reversals.append(self.value)
                # Levitt (1971): shrink the step over the first few reversals.
                if len(self.reversals)<=self.step_reduction_reversals:self.current_step=max(self.min_step,self.current_step*self.step_factor)
            self.last_direction=direction;self.value=max(self.minimum,min(self.maximum,self.value+direction*self.current_step))
        return self.value
    @property
    def complete(self):return len(self.reversals)>=self.stop_reversals
    @property
    def target_proportion(self):
        # n-down/1-up converges on P = 0.5**(1/n) correct (Levitt, 1971).
        return 0.5**(1/self.rule_correct)
    def threshold(self,last:int=6):return mean(self.reversals[-last:]) if len(self.reversals)>=last else None
    def threshold_sd(self,last:int=6):
        if len(self.reversals)<last:return None
        w=self.reversals[-last:];m=mean(w)
        return (sum((x-m)**2 for x in w)/len(w))**0.5

@dataclass
class Trial:
    target:str;response:str;correct:bool;latency_ms:int;replays:int=0
class Score:
    def __init__(self):self.trials:list[Trial]=[]
    def add(self,t:Trial):self.trials.append(t)
    @property
    def accuracy(self):return sum(t.correct for t in self.trials)/len(self.trials) if self.trials else 0
    def confusion(self):
        labels=sorted({v for t in self.trials for v in (t.target,t.response)})
        out={a:{b:0 for b in labels} for a in labels}
        for t in self.trials:out[t.target][t.response]+=1
        return out
    def reliability(self,min_trials=20,max_replay=.35,max_fast=.15):
        if len(self.trials)<min_trials:return {'reliable':False,'reason':'insufficient_trials'}
        replay=sum(t.replays>0 for t in self.trials)/len(self.trials)
        fast=sum(t.latency_ms<180 for t in self.trials)/len(self.trials)
        return {'reliable':replay<=max_replay and fast<=max_fast,'replay_rate':replay,'fast_rate':fast}

def snr_staircase(start=12):return Staircase(start,-12,20,2,'down',2,8)
def gap_staircase(start_ms=20):return Staircase(start_ms,.5,100,4,'down',2,8,step_factor=.5,step_reduction_reversals=2,min_step=1)
def modulation_staircase(start_db=-6):return Staircase(start_db,-40,0,4,'down',2,8,step_factor=.5,step_reduction_reversals=2,min_step=1)
def frequency_staircase(start_semitones=6):return Staircase(start_semitones,.25,12,2,'down',2,8,step_factor=.5,step_reduction_reversals=2,min_step=.25)
