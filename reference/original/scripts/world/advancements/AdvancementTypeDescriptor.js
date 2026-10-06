class AdvancementTypeDescriptor{
    constructor(name, description, costs, effects){
        this.name = name;
        this.description=description;
        this.costs = costs;
        this.effects = effects;
    }
    getName(){
        return this.name;
    }
    getDescription(){
        return this.description;
    }
    getMaximumLevel(){
        return this.costs.length;
    }
    getCost(level){
        return this.costs[level];
    }
    getEffect(level){
        return this.effects[level];
    }
    getEffectDescription(level){
        throw "getEffectDescription is a virtual method";
    }
}