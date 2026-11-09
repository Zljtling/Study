#include "exercises.h"
#include <iostream>
using namespace std;

void exercise9()
{
	struct CandyBar
	{
		char brand[20];
		float weight;
		unsigned int calorie;
	};
	CandyBar* pc = new CandyBar[3];
	strcpy_s(pc[0].brand, "Mocha Munch");
	pc[0].weight = 2.3;
	pc[0].calorie = 350;
	strcpy_s(pc[1].brand, "Hershey bar");
	pc[1].weight = 4.2;
	pc[1].calorie = 550;
	strcpy_s(pc[2].brand, "Musketeers");
	pc[2].weight = 2.6;
	pc[2].calorie = 550;

	cout << pc->brand << " " << pc->weight << " " << pc->calorie << endl;
	cout << (pc + 1)->brand << " " << (pc + 1)->weight << " " << (pc + 1)->calorie << endl;
	cout << (pc + 2)->brand << " " << (pc + 2)->weight << " " << (pc + 2)->calorie << endl;
	delete[]pc;
}