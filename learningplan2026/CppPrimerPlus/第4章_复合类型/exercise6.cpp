#include "exercises.h"
#include <iostream>
using namespace std;

void exercise6()
{
	struct CandyBar
	{
		char brand[20];
		float weight;
		unsigned int calorie;
	};
	CandyBar snack[3] = {{"Mocha Munch", 2.3, 350} ,{"Hershey bar", 4.2, 550},{"Musketeers", 2.6,430}};
	for (int i = 0; i < 3; i++)
	{
		cout << snack[i].brand << " " << snack[i].weight << " " << snack[i].calorie << endl;
	}
}